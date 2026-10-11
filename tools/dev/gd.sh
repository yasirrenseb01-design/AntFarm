#!/usr/bin/env bash
# Run Godot only if every script parses (a parse error makes Godot hang with a black window).
# Usage: tools/dev/gd.sh [godot args...]     e.g. tools/dev/gd.sh --path . -- --shot=shots/x.png
G=/e/Godot_v4.7.2-stable_win64_console.exe
cd "$(dirname "$0")/../.."
err=$(timeout 60 $G --headless --path . --check-only --script res://scripts/game/main.gd 2>&1 | grep "SCRIPT ERROR" | head -3)
if [ -n "$err" ]; then
  echo "PARSE ERROR - not running:"; echo "$err"
  for f in $(git ls-files 'scripts/*.gd'); do
    e=$(timeout 30 $G --headless --path . --check-only --script res://$f 2>&1 | grep -A1 "Parse Error" | grep -v "resolve\|Failed to compile" | head -2)
    [ -n "$e" ] && echo "  $f: $e"
  done
  exit 1
fi
timeout ${GD_TIMEOUT:-300} $G "$@"
