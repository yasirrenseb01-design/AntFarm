# Builds the measuring copy of the game (build\measure\AntFarm-measure.exe): the same release engine and files as the
# player's exe, but it keeps the developer's command-line options (--testsave, --perf, --hitch-log, --view, ...) that the
# player's exe drops - so the frame rate is measured on what the players run (the editor build is slower). Never given
# to players and never put in a zip (tools/package.ps1 takes build\AntFarm.exe only). PART 0.12 step 7.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$godot = "E:\Godot_v4.7.2-stable_win64_console.exe"
$keyFile = "E:\GodotBuild\antfarm_pck.key"
if (-not (Test-Path $keyFile)) { throw "encryption key missing ($keyFile): see docs/release/ENCRYPTION.md" }
New-Item -ItemType Directory -Force "$root\build\measure" | Out-Null
$env:GODOT_SCRIPT_ENCRYPTION_KEY = (Get-Content $keyFile -Raw).Trim()
& $godot --headless --path $root --export-release "Windows Measure" "$root\build\measure\AntFarm-measure.exe"
Remove-Item Env:\GODOT_SCRIPT_ENCRYPTION_KEY
if (-not (Test-Path "$root\build\measure\AntFarm-measure.exe")) { throw "export failed" }
Write-Output "built $root\build\measure\AntFarm-measure.exe"
