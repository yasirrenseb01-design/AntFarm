#!/usr/bin/env bash
# Builds the C++ part (native/ -> bin/ant_native.windows.<target>.x86_64.dll), PART 0.12 step 4.
# Needs: native/godot-cpp (git clone https://github.com/godotengine/godot-cpp, the commit in native/GODOT_CPP_COMMIT),
# the llvm-mingw compiler in /e/toolchain (github.com/mstorsjo/llvm-mingw 20261020), scons (pip install scons).
# native/extension_api.json is dumped from the Godot the game runs on: godot --headless --dump-extension-api
# Usage: tools/native.sh [template_debug|template_release|both]
cd "$(dirname "$0")/../native"
export PATH="/e/toolchain/llvm-mingw-20261020-ucrt-x86_64/bin:$PATH"
t="${1:-both}"
[ -f extension_api.json ] || /e/Godot_v4.7.2-stable_win64_console.exe --headless --dump-extension-api >/dev/null 2>&1
for tg in template_debug template_release; do
  [ "$t" != "both" ] && [ "$t" != "$tg" ] && continue
  scons platform=windows use_mingw=yes use_llvm=yes target=$tg custom_api_file="$(pwd -W)/extension_api.json" -j8 2>&1 | grep -i "error\|warning: \|Linking Shared\|done building" | head -20
done
rm -f ../bin/libant_native.*.a
# (Godot loads an extension listed here; the editor writes it when it scans the project, a headless run does not)
grep -q "ant_native.gdextension" ../.godot/extension_list.cfg 2>/dev/null || echo "res://bin/ant_native.gdextension" >> ../.godot/extension_list.cfg
ls -la ../bin
