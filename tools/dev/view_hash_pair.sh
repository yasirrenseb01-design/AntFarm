#!/usr/bin/env bash
# The nest view's --view-hash of this checkout and of another (a git worktree of the version before), on the keeper's
# colony copy (usercopy slot 3, at the default and at high quality: 250 / 600 drawn) and a small nest (slot 1): the
# lines must be equal for a change that should not alter the picture (v0.12.27).
# Usage: tools/dev/view_hash_pair.sh <other checkout> [extra option...]
other="$1"; shift
cd "$(dirname "$0")/../.."
here="$(pwd)"
for run in "--slot=3" "--slot=3 --quality=high" "--slot=1"; do
  for dir in "$other" "$here"; do
    h=$(GD_TIMEOUT=600 "$here/tools/dev/gd.sh" --path "$dir" --fixed-fps 60 -- --sandbox --tod=0.5 --live --frames=300 --view-hash=7 \
      --shot=shots/hash.png --testsave=usercopy $run --view=nest "$@" 2>&1 | grep "view hash")
    echo "$run | $(basename "$dir") | $h"
  done
done
