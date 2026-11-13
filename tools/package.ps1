# The release zips (PART EA-R R5): the archived build of this version, AntDesk.exe (the wallpaper helper), README,
# PRIVACY, CREDITS (R6) and the engine's licence notices, zipped as build\release\AntFarm-v<version>-windows.zip with
# its SHA-256 in a .sha256 file beside it (and printed) - the keeper puts both on the store page. Since v0.13.18 the free
# demo too (build\demo\AntFarm-demo-v<version>.exe, scripts/game/demo.gd), as AntFarm-v<version>-demo-windows.zip,
# uploaded beside it and marked "demo". Build first (tools/build.ps1 makes both).
#   powershell -ExecutionPolicy Bypass -File tools/package.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$godot = "E:\Godot_v4.7.2-stable_win64_console.exe"
$version = (Select-String -Path "$root\project.godot" -Pattern 'config/version="([^"]+)"').Matches[0].Groups[1].Value
$exe = "$root\build\versions\AntFarm-v$version.exe"
$demo = "$root\build\demo\AntFarm-demo-v$version.exe"
$desk = "$root\build\AntDesk.exe"
if (-not (Test-Path $exe)) { throw "no build of v$version ($exe): run tools/dev/release.sh first" }
if (-not (Test-Path $demo)) { throw "no demo build of v$version ($demo): run tools/build.ps1" }
if (-not (Test-Path $desk)) { throw "no AntDesk.exe: run tools/build.ps1" }
$out = "$root\build\release"

# one zip: the exe given (named $exeName in it), AntDesk, the C++ part, the notes and the licences
function Pack([string]$src, [string]$exeName, [string]$tag) {
    $stage = "$out\AntFarm-v$version$tag"
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Force $stage | Out-Null
    Copy-Item $src "$stage\$exeName"
    Copy-Item $desk "$stage\AntDesk.exe"
    # the C++ part beside the exe (v0.12.6): without it the game runs on, its GDScript doing the same, a little slower
    Get-ChildItem "$root\build\versions" -Filter "ant_native.*.dll" | ForEach-Object { Copy-Item $_.FullName "$stage\$($_.Name)" }
    Copy-Item "$root\docs\release\README.txt" "$stage\README.txt"
    Copy-Item "$root\docs\release\PRIVACY.md" "$stage\PRIVACY.txt"
    Copy-Item "$root\docs\release\CREDITS.txt" "$stage\CREDITS.txt"
    & $godot --headless --path $root --script res://tools/dev/license_text.gd -- "$stage\THIRD_PARTY_LICENSES.txt" | Out-Null
    if (-not (Test-Path "$stage\THIRD_PARTY_LICENSES.txt")) { throw "licence notices not written" }
    $zip = "$out\AntFarm-v$version$tag-windows.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path "$stage\*" -DestinationPath $zip
    $hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
    "$hash  AntFarm-v$version$tag-windows.zip" | Set-Content -Encoding ascii "$zip.sha256"
    $size = [math]::Round((Get-Item $zip).Length / 1MB, 1)
    Write-Output "packed $zip ($size MB)"
    Write-Output "SHA-256 $hash"
}
Pack $exe "AntFarm.exe" ""
Pack $demo "AntFarm-demo.exe" "-demo"

# Old release zips (2026-11-08: 16 of them had piled up, 2.5 GB): keep this version and every version tagged store-v<ver>
# (what is or was on the store); remove the rest, folder, zip and .sha256 alike (the demo's with them).
$store = @(git -C $root tag --list "store-v*" | ForEach-Object { $_ -replace '^store-v', '' }) + $version
Get-ChildItem $out | Where-Object { $_.Name -match '^AntFarm-v(\d+\.\d+\.\d+)' -and $store -notcontains $Matches[1] } | ForEach-Object {
    try { Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop; Write-Output "removed old release $($_.Name)" } catch {}
}
