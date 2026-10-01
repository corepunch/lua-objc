#!/bin/sh
# Measures what a fresh worktree of this repository costs: the checked-out
# source, Git's own record of the worktree, and (with --submodules NAME…) the
# submodules a task asked for. The shared object database is not counted once
# per worktree. Exits nonzero above LIMIT_MB (default 100).
#
#   scripts/workspace-size.sh                         # source only
#   scripts/workspace-size.sh --submodules lua/vendor/etlua
set -eu
limit_mb=${LIMIT_MB:-100}
repo=$(git rev-parse --show-toplevel)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/workspace-size.XXXXXX")
trap 'git -C "$repo" worktree remove --force "$tmp/wt" >/dev/null 2>&1 || true; rm -rf "$tmp"' EXIT
git -C "$repo" worktree add --detach "$tmp/wt" HEAD >/dev/null 2>&1
if [ "${1:-}" = "--submodules" ]; then
	shift
	for path in "$@"; do git -C "$tmp/wt" -c protocol.file.allow=always submodule update --init --depth 1 "$path" >/dev/null 2>&1; done
fi
kb() { du -sk "$1" | cut -f1; }
admin=$(git -C "$tmp/wt" rev-parse --absolute-git-dir)
checkout=$(( $(kb "$tmp/wt") ))
record=$(( $(kb "$admin") ))
total=$(( checkout + record ))
printf 'checkout (source and requested submodules)  %8d KB\n' "$checkout"
printf "Git's record of this worktree                %8d KB\n" "$record"
printf 'incremental total                            %8d KB (limit %d MB)\n' "$total" "$limit_mb"
[ "$total" -le $(( limit_mb * 1024 )) ]
