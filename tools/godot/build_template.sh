#!/bin/bash
# Builds the Godot 4.7.2 Windows release export template with AntFarm's pck encryption key (E:\GodotBuild\antfarm_pck.key)
cd /e/GodotBuild/godot
export PATH="/e/GodotBuild/llvm-mingw-20261006-ucrt-x86_64/bin:$PATH"
export SCRIPT_AES256_ENCRYPTION_KEY=$(tr -d '\r\n' < /e/GodotBuild/antfarm_pck.key)
scons platform=windows target=template_release arch=x86_64 production=yes use_mingw=yes use_llvm=yes \
  mingw_prefix=/e/GodotBuild/llvm-mingw-20261006-ucrt-x86_64 d3d12=yes accesskit=no -j10 > /e/GodotBuild/build.log 2>&1
echo "exit $?" >> /e/GodotBuild/build.log
