#!/usr/bin/env bash
# Name a project clone's GitHub repository from the clone's own remotes.
# Prints exactly one line, <owner>/<repo>, and exits 0 when the repository is
# unambiguous; prints nothing and exits 1 when it is not; exits 2 with an error
# on stderr for a missing clone or a directory that is not a git work tree.
#
# bin/fm-spawn.sh exports the result as GH_REPO into every ship and scout
# launch. gh and gh-axi infer the repository of an issue, PR, or comment command
# from the git remote of the shell's current directory, so a worker whose shell
# sits inside the firstmate home would otherwise address the firstmate repo
# itself. GH_REPO pins those commands to the task's project from any directory,
# and an explicit --repo still overrides it.
#
# Only remotes on github.com (including ssh.github.com) count, read from the
# clone's own git config and never from the network:
#   1. a remote chosen with `gh repo set-default` (remote.<name>.gh-resolved)
#      names the repository;
#   2. otherwise the repository is the one owner/repo every GitHub remote
#      shares.
# Remotes naming different repositories with no set-default choice (a fork
# layout such as origin plus upstream) are ambiguous and resolve to nothing,
# which leaves gh's own resolution unchanged; recording the choice with
# `gh repo set-default` in the clone resolves it. A clone with no GitHub remote,
# or a GH_HOST naming another host, also resolves to nothing.
# Usage: fm-gh-repo.sh <clone-dir>
set -eu

DIR=${1:?usage: fm-gh-repo.sh <clone-dir>}
if [ ! -d "$DIR" ] || ! git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: $DIR is not a git work tree" >&2
  exit 2
fi

# Print owner/repo for a github.com remote URL; fail for anything else.
github_slug() {  # <url>
  local url=$1 host path
  case "$url" in
    *://*)
      url=${url#*://}
      host=${url%%/*}
      path=${url#*/}
      [ "$path" != "$url" ] || return 1
      ;;
    *:*)
      host=${url%%:*}
      path=${url#*:}
      ;;
    *) return 1 ;;
  esac
  host=${host##*@}
  host=${host%%:*}
  case "$host" in
    github.com|ssh.github.com) ;;
    *) return 1 ;;
  esac
  path=${path%/}
  path=${path%.git}
  case "$path" in
    */*/* | /* | */ | *[!A-Za-z0-9._/-]*) return 1 ;;
    ?*/?*) printf '%s\n' "$path" ;;
    *) return 1 ;;
  esac
}

case "${GH_HOST:-github.com}" in
  github.com) ;;
  *) exit 1 ;;
esac

REMOTES=$(git -C "$DIR" remote 2>/dev/null || true)
slug=
chosen=
while IFS= read -r remote; do
  [ -n "$remote" ] || continue
  url=$(git -C "$DIR" remote get-url "$remote" 2>/dev/null) || continue
  s=$(github_slug "$url") || continue
  # gh records `base` on the chosen remote.
  if [ "$(git -C "$DIR" config --get "remote.$remote.gh-resolved" 2>/dev/null || true)" = base ]; then
    chosen=$s
  fi
  if [ -n "$slug" ] && [ "$slug" != "$s" ]; then
    slug=ambiguous
  elif [ -z "$slug" ]; then
    slug=$s
  fi
done <<EOF
$REMOTES
EOF
if [ -n "$chosen" ]; then
  printf '%s\n' "$chosen"
elif [ -n "$slug" ] && [ "$slug" != ambiguous ]; then
  printf '%s\n' "$slug"
else
  exit 1
fi
