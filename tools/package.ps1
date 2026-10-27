# The release zip (PART EA-R R5): the archived build of this version, AntDesk.exe (the wallpaper helper), README,
# PRIVACY and the engine's licence notices, zipped as build\release\AntFarm-v<version>-windows.zip with its SHA-256 in
# a .sha256 file beside it (and printed) - the keeper puts both on the store page. Build first (tools/dev/release.sh).
#   powershell -ExecutionPolicy Bypass -File tools/package.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$godot = "E:\Godot_v4.7.2-stable_win64_console.exe"
$version = (Select-String -Path "$root\project.godot" -Pattern 'config/version="([^"]+)"').Matches[0].Groups[1].Value
$exe = "$root\build\versions\AntFarm-v$version.exe"
$desk = "$root\build\AntDesk.exe"
if (-not (Test-Path $exe)) { throw "no build of v$version ($exe): run tools/dev/release.sh first" }
if (-not (Test-Path $desk)) { throw "no AntDesk.exe: run tools/build.ps1" }
$out = "$root\build\release"
$stage = "$out\AntFarm-v$version"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item $exe "$stage\AntFarm.exe"
Copy-Item $desk "$stage\AntDesk.exe"
Copy-Item "$root\docs\release\README.txt" "$stage\README.txt"
Copy-Item "$root\docs\release\PRIVACY.md" "$stage\PRIVACY.txt"
& $godot --headless --path $root --script res://tools/dev/license_text.gd -- "$stage\THIRD_PARTY_LICENSES.txt" | Out-Null
if (-not (Test-Path "$stage\THIRD_PARTY_LICENSES.txt")) { throw "licence notices not written" }
$zip = "$out\AntFarm-v$version-windows.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path "$stage\*" -DestinationPath $zip
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
"$hash  AntFarm-v$version-windows.zip" | Set-Content -Encoding ascii "$zip.sha256"
$size = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Output "packed $zip ($size MB)"
Write-Output "SHA-256 $hash"
