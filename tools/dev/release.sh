#!/usr/bin/env bash
# Release gate: run every check and build only if they all pass (a failing check must never slip
# through a pipe like `check | tail && build`). Commit/push stay manual, after reading the output.
# Usage: tools/dev/release.sh
cd "$(dirname "$0")/../.."
OUT=$(powershell -NoProfile -File tools/check.ps1 2>&1)
echo "$OUT" | tail -12
if ! echo "$OUT" | grep -q "ALL CHECKS PASSED"; then
  echo "=> CHECKS FAILED: not building. Fix first."
  exit 1
fi
powershell -NoProfile -File tools/build.ps1 2>&1 | grep "built\|removed"
