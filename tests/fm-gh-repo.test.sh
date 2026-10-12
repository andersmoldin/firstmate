#!/usr/bin/env bash
# bin/fm-gh-repo.sh names a project clone's GitHub repository from the clone's
# own remotes, so a worker's repository-inferring gh commands can be pinned to
# the project rather than to whatever repository the worker's shell sits in.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-gh-repo-tests)
RESOLVE="$ROOT/bin/fm-gh-repo.sh"

new_clone() {  # <name>
  local dir="$TMP_ROOT/$1"
  git init -q "$dir"
  printf '%s\n' "$dir"
}

test_single_github_origin_names_the_repository() {
  local clone url out
  for url in git@github.com:acme/widget.git https://github.com/acme/widget \
    ssh://git@ssh.github.com:443/acme/widget.git https://token@github.com/acme/widget.git/; do
    clone=$(new_clone "origin-$(printf '%s' "$url" | tr -c 'a-z0-9' '-')")
    git -C "$clone" remote add origin "$url"
    out=$(env -u GH_HOST "$RESOLVE" "$clone") || fail "a clone whose origin is $url resolved nothing"
    assert_equals acme/widget "$out" "a clone whose origin is $url must resolve to its GitHub repository"
  done
  pass "a clone with one GitHub origin resolves to owner/repo across URL forms"
}

test_fork_layout_without_a_default_is_ambiguous() {
  local clone out status
  clone=$(new_clone fork-ambiguous)
  git -C "$clone" remote add origin git@github.com:someone/widget.git
  git -C "$clone" remote add upstream https://github.com/acme/widget.git
  out=$(env -u GH_HOST "$RESOLVE" "$clone")
  status=$?
  expect_code 1 "$status" "a fork layout with no set-default choice must not guess a repository"
  assert_equals "" "$out" "an ambiguous clone must print nothing"
  pass "remotes naming different GitHub repositories with no set-default choice resolve to nothing"
}

test_set_default_choice_wins() {
  local clone out
  clone=$(new_clone fork-default)
  git -C "$clone" remote add origin git@github.com:someone/widget.git
  git -C "$clone" remote add upstream https://github.com/acme/widget.git
  # The exact config `gh repo set-default acme/widget` records on the remote.
  git -C "$clone" config remote.upstream.gh-resolved base
  out=$(env -u GH_HOST "$RESOLVE" "$clone") || fail "a clone with a set-default choice resolved nothing"
  assert_equals acme/widget "$out" "the gh repo set-default choice must name the repository"
  pass "a gh repo set-default choice resolves a fork layout to the chosen repository"
}

test_same_repository_on_several_remotes_is_unambiguous() {
  local clone out
  clone=$(new_clone same-repo)
  git -C "$clone" remote add origin git@github.com:acme/widget.git
  git -C "$clone" remote add mirror https://github.com/acme/widget
  git -C "$clone" remote add gate /tmp/not-a-forge.git
  out=$(env -u GH_HOST "$RESOLVE" "$clone") || fail "remotes sharing one GitHub repository resolved nothing"
  assert_equals acme/widget "$out" "remotes sharing one repository must resolve to it"
  pass "several remotes naming one GitHub repository, beside a non-GitHub remote, resolve to it"
}

test_non_github_and_remote_less_clones_resolve_nothing() {
  local clone out status
  clone=$(new_clone gitlab)
  git -C "$clone" remote add origin git@gitlab.com:acme/widget.git
  out=$(env -u GH_HOST "$RESOLVE" "$clone")
  status=$?
  expect_code 1 "$status" "a GitLab origin must not resolve to a GitHub repository"
  assert_equals "" "$out" "a GitLab origin must print nothing"
  clone=$(new_clone local-only)
  out=$(env -u GH_HOST "$RESOLVE" "$clone")
  status=$?
  expect_code 1 "$status" "a clone with no remote must resolve to nothing"
  pass "a non-GitHub or remote-less clone resolves to nothing"
}

test_other_gh_host_resolves_nothing() {
  local clone out status
  clone=$(new_clone ghe-host)
  git -C "$clone" remote add origin git@github.com:acme/widget.git
  # gh reads an unqualified GH_REPO against GH_HOST, so owner/repo would point
  # the worker at the same path on the enterprise host.
  out=$(GH_HOST=git.example.com "$RESOLVE" "$clone")
  status=$?
  expect_code 1 "$status" "a GH_HOST naming another host must not pin a github.com repository"
  out=$(GH_HOST=github.com "$RESOLVE" "$clone") || fail "GH_HOST=github.com resolved nothing"
  assert_equals acme/widget "$out" "GH_HOST=github.com must still resolve the repository"
  pass "a GH_HOST naming another host resolves nothing, while GH_HOST=github.com still resolves"
}

test_not_a_work_tree_is_an_error() {
  local out status
  mkdir -p "$TMP_ROOT/plain"
  out=$("$RESOLVE" "$TMP_ROOT/plain" 2>&1)
  status=$?
  expect_code 2 "$status" "a directory that is not a git work tree must be an error: $out"
  pass "a directory that is not a git work tree exits 2"
}

test_single_github_origin_names_the_repository
test_fork_layout_without_a_default_is_ambiguous
test_set_default_choice_wins
test_same_repository_on_several_remotes_is_unambiguous
test_non_github_and_remote_less_clones_resolve_nothing
test_other_gh_host_resolves_nothing
test_not_a_work_tree_is_an_error
