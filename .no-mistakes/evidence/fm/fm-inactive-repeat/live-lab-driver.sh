#!/usr/bin/env bash
# Live driver: real firstmate scripts against a disposable lab home.
# usage: drive.sh <repo-root> <scenario>
set -u
ROOT=$1 SCEN=$2
BIN="$ROOT/bin"
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
rmdir "$LAB"; "$BIN/fm-lab-home.sh" create "$LAB" >/dev/null || exit 1
TD=$("$BIN/fm-lab-home.sh" tmux-dir "$LAB") || exit 1
cleanup() { TMUX_TMPDIR="$TD" tmux -L fm-lab kill-server 2>/dev/null; "$BIN/fm-lab-home.sh" teardown "$LAB"; rm -rf "$LAB"; }
trap cleanup EXIT
export FM_HOME="$LAB"
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE NO_MISTAKES_GATE FM_GATE_REFUSE_BYPASS TMUX
export TMUX_TMPDIR="$TD"
export FM_INACTIVE_RECONCILE_SECS=60
S="$LAB/state"
PR=https://github.com/andersmoldin/aslan-private/pull/151
ID=aslan-ikon-beskuren
old() { local t; t=$(date -r $(( $(date +%s) - 300 )) +%Y%m%d%H%M.%S); touch -t "$t" "$@"; }
say() { printf '\n$ %s\n' "$*"; }
run() { say "$*"; "$@"; rc=$?; printf '[exit %s]\n' "$rc"; return $rc; }

# A finished ship child whose PR is recorded and whose head is reachable on origin.
mkdir -p "$LAB/projects/$ID"
git -C "$LAB/projects/$ID" init -q
git -C "$LAB/projects/$ID" -c user.name=lab -c user.email=lab@example.invalid commit -q --allow-empty -m init
SHA=$(git -C "$LAB/projects/$ID" rev-parse HEAD)
git -C "$LAB/projects/$ID" update-ref refs/remotes/origin/main "$SHA"
cat > "$S/$ID.meta" <<EOF
window=firstmate:fm-$ID
worktree=$LAB/projects/$ID
project=$LAB/projects/$ID
harness=claude
kind=ship
mode=no-mistakes
yolo=off
spawn_gen=lab.1
pr=$PR
pr_head=$SHA
EOF
printf 'done: PR %s checks green\n' "$PR" > "$S/$ID.status"
: > "$S/$ID.turn-ended"
# The child's Claude Stop hook recorded its turn as finished (the real busy-state writer).
"$BIN/fm-busy-event.sh" arm "$S" "$ID" --state idle --source claude-hook --event stop >/dev/null || exit 1
old "$S/$ID.meta" "$S/$ID.status" "$S/$ID.turn-ended" "$S/$ID.busy-state" "$S/$ID.busy-gen"

# The child's real tmux window on the lab's private socket, idle at a prompt.
tmux -L fm-lab new-session -d -s firstmate -n "fm-$ID" -x 120 -y 30 "sh -c 'printf \"> \"; exec cat'"
export TMUX="$TD/tmux-$(id -u)/fm-lab,0,0"
sleep 1
echo "lab tmux: $(tmux list-windows -a -F '#{session_name}:#{window_name}')"
echo "== scenario: $SCEN  (FM_HOME=lab home, real fm-crew-state.sh, real branch-outcome store)"
run "$BIN/fm-crew-state.sh" "$ID"
say "supervision-host records the captain BRANCH OUTCOME for PR 151"
SEQ=$("$BIN/fm-branch-outcome.sh" append --task "$ID" --verdict captain --summary "$ID is ready for review: $PR"); echo "seq=$SEQ"
run "$BIN/fm-branch-outcome.sh" mark-read --through "$SEQ"
case "$SCEN" in
  processed-first)
    run "$BIN/fm-branch-outcome.sh" mark-processed --through "$SEQ"
    run "$BIN/fm-inactive-reconcile.sh" scan --startup ;;
  scan-first-drain-now|scan-first-rescan)
    run "$BIN/fm-inactive-reconcile.sh" scan --startup
    say "wake queue after scan"; cat "$S/.wake-queue" 2>/dev/null || echo '(empty)'
    run "$BIN/fm-branch-outcome.sh" mark-processed --through "$SEQ"
    if [ "$SCEN" = scan-first-rescan ]; then old "$S/.inactive-outcome-reconcile"; run "$BIN/fm-inactive-reconcile.sh" scan; fi ;;
  read-only)
    run "$BIN/fm-inactive-reconcile.sh" scan --startup ;;
  failed-after)
    run "$BIN/fm-branch-outcome.sh" mark-processed --through "$SEQ"
    printf 'failed: the PR was closed after review\n' >> "$S/$ID.status"; old "$S/$ID.status"
    run "$BIN/fm-inactive-reconcile.sh" scan --startup ;;
  other-pr)
    sed -i '' 's#pull/151#pull/15#' "$S/$ID.meta"
    printf 'done: PR %s checks green\n' "${PR%151}15" > "$S/$ID.status"; old "$S/$ID.status" "$S/$ID.meta"
    # store still names pull/151 in the summary, but provenance captured the earlier status; rebuild: append fresh outcome for pull/151 is n/a
    run "$BIN/fm-branch-outcome.sh" mark-processed --through "$SEQ"
    run "$BIN/fm-inactive-reconcile.sh" scan --startup ;;
esac
say "wake queue before drain"; cat "$S/.wake-queue" 2>/dev/null || echo '(empty)'
say "terminal-outcome receipts"; ls "$S/terminal-outcomes" 2>/dev/null
say "fm-wake-drain.sh (what main sees)"
"$BIN/fm-wake-drain.sh" > "$LAB/drain.out" 2> "$LAB/drain.err"; echo "[exit $?]"
echo "--- stdout"; cat "$LAB/drain.out"; echo "--- stderr"; cat "$LAB/drain.err"
ACK=$(sed -n 's/^WAKE_ACK_REQUIRED: *\(.*\)$/\1/p' "$LAB/drain.err" | head -1)
SEQA=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--ack-through \([0-9][0-9]*\) --recovery-generation .*/\1/p' "$LAB/drain.err")
GEN=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--recovery-generation \([A-Za-z0-9._-][A-Za-z0-9._-]*\)$/\1/p' "$LAB/drain.err")
if [ -n "$SEQA" ]; then
  run "$BIN/fm-wake-drain.sh" --ack-through "$SEQA" --recovery-generation "$GEN" >/dev/null
  say "wake queue after acknowledgement"; cat "$S/.wake-queue" 2>/dev/null || echo '(empty)'
  say "receipts after acknowledgement"; ls "$S/terminal-outcomes"
fi
say "second drain (repeat check)"
"$BIN/fm-wake-drain.sh" 2>&1 | grep -E 'awaiting captain presentation|inactive-outcome' || echo '(no inactive-outcome rows)'
