#!/usr/bin/env bash
# Live drive of fm-captain-hold.sh reason/append against a disposable lab home.
set -u
WT=$1
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$WT/bin/fm-lab-home.sh" create "$LAB" >/dev/null || { echo "lab create failed"; exit 1; }
cat > "$LAB/.tasks.toml" <<'TOML'
backend = "markdown"

[markdown]
path = "data/backlog.md"
archive = "data/done-archive.md"
done_keep = 10
TOML
printf '## In flight\n\n## Queued\n\n## Done\n' > "$LAB/data/backlog.md"
cap() { env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME="$LAB" "$WT/bin/fm-captain-hold.sh" "$@"; }
tx() { (cd "$LAB" && tasks-axi "$@"); }
step() { printf '\n=== %s\n' "$*"; }
run() { printf '$ %s\n' "$*"; "$@"; rc=$?; printf '[exit %s]\n' "$rc"; return $rc; }

step "S1: hold a captain call whose reason has quotes, slashes, \\/, åäö and a line break"
REASON=$'Välj "A" eller B/C, inte \\/ (se åäö)\nandra raden'
run cap hold demo-call --title "Demo call" --reason "$REASON" --repo sample --until 2030-01-02
step "S1: reason prints it as plain text"
run cap reason demo-call
GOT=$(cap reason demo-call); [ "$GOT" = "$REASON" ] && echo "CHECK exact round trip: OK" || echo "CHECK exact round trip: FAIL"
step "raw backlog line (what used to be decoded by hand)"
grep -n "demo-call" "$LAB/data/backlog.md" | cut -c1-200

step "S2: append eight captain answers, one at a time (the retrospective's ~8 times)"
for i in 1 2 3 4 5 6 7 8; do
  printf 'Svar %s: "ja" via a/b\\/c, ändra ö\n' "$i" > "$LAB/ans$i.txt"
  cap append demo-call --text-file "$LAB/ans$i.txt" >/dev/null || echo "append $i FAILED"
done
run cap reason demo-call
EXPECT="$REASON"; for i in 1 2 3 4 5 6 7 8; do EXPECT+=$'\n'"Svar $i: \"ja\" via a/b\\/c, ändra ö"; done
[ "$(cap reason demo-call)" = "$EXPECT" ] && echo "CHECK eight appends exact, \\/ intact: OK" || echo "CHECK eight appends: FAIL"
step "S2: hold kind, --until and hold-set stamp preserved"
tx show demo-call --full | grep -E "held|hold_kind|hold_until|state"
grep -q "Captain hold set:" "$LAB/data/backlog.md" && echo "CHECK hold-set stamp present: OK" || echo "CHECK stamp: FAIL"

step "S3: kindless hold (tasks-axi hold without --kind) stays kindless after append"
tx add plain-later "Start later" --repo sample >/dev/null
tx hold plain-later --reason "start later" --until 2030-01-01 >/dev/null
tx show plain-later --full | grep -E "hold_kind|hold_until"
printf 'notering\n' > "$LAB/note.txt"
run cap append plain-later --text-file "$LAB/note.txt"
run cap reason plain-later
tx show plain-later --full | grep -E "hold_kind|hold_until"
tx show plain-later --full | grep -q "hold_kind: captain" && echo "CHECK not promoted: FAIL" || echo "CHECK not promoted to captain: OK"

step "S4: hold whose --until date has passed"
run cap hold old-call --title "Old call" --reason "gammal orsak" --repo sample --until 2020-01-01 >/dev/null
tx show old-call --full | grep -E "held|hold_until"
run cap append old-call --text-file "$LAB/note.txt"
run cap reason old-call
tx show old-call --full | grep -E "held|hold_kind|hold_until"

step "S5: adversarial refusals (each must exit non-zero and leave the reason unchanged)"
BEFORE=$(cap reason demo-call)
: > "$LAB/empty.txt"
run cap append demo-call --text-file "$LAB/empty.txt"
run cap append demo-call --text-file "$LAB/missing.txt"
run cap append demo-call
head -c 8193 /dev/zero | tr '\0' x > "$LAB/big.txt"
run cap append demo-call --text-file "$LAB/big.txt"
head -c 8192 /dev/zero | tr '\0' y > "$LAB/edge.txt"
tx add not-held "Not held" --repo sample >/dev/null
run cap append not-held --text-file "$LAB/note.txt"
run cap reason not-held
run cap reason no-such-task
run cap append "../evil" --text-file "$LAB/note.txt"
run cap append demo-call --text-file "$LAB/note.txt" --bogus
[ "$(cap reason demo-call)" = "$BEFORE" ] && echo "CHECK reason unchanged after refusals: OK" || echo "CHECK unchanged: FAIL"
step "S5: closed task refused"
tx add closed-one "Closed" --repo sample >/dev/null
tx hold closed-one --reason "x" >/dev/null
tx done closed-one >/dev/null 2>&1 || tx update closed-one --state done >/dev/null 2>&1
tx show closed-one --full | grep -E "^ *state"
run cap append closed-one --text-file "$LAB/note.txt"
run cap reason closed-one
step "S5: exactly 8192 bytes accepted"
cap hold edge-call --title "Edge" --reason "kant" --repo sample >/dev/null
run cap append edge-call --text-file "$LAB/edge.txt"
[ "$(cap reason edge-call | tail -1 | wc -c | tr -d ' ')" = 8193 ] && echo "CHECK 8192-byte append stored: OK" || echo "CHECK 8192: FAIL"

step "S6: appended captain call is still answerable and resolves"
printf 'Kör A.\n' > "$LAB/decision.txt"
run cap answer demo-call --decision-file "$LAB/decision.txt" --release
tx show demo-call --full | grep -E "state|held"
rm -rf "$LAB"; [ -e "$LAB" ] || echo "lab removed"
