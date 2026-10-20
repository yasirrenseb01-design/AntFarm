# Runs every check before a release (see docs/WORKFLOW.md):
#   1. parse-check every script (a script with a parse error would hang the game, so this goes first)
#   2. save round trip, obstacle reach, and the keeper's real colony (copy in user://sandbox) if present
#   3. determinism: a fixed-seed self-test must match tests/baselines/ (unless the change is intended:
#      then run with -UpdateBaseline and say so in the CHANGELOG)
#   4. speed: a 300-worker colony in the 3D outworld and the nest (skipped with -Quick)
# Usage:  powershell -ExecutionPolicy Bypass -File tools/check.ps1 [-Quick] [-UpdateBaseline]
param([switch]$Quick, [switch]$UpdateBaseline)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$godot = "E:\Godot_v4.7.2-stable_win64_console.exe"
$fail = 0
Set-Location $root

function Run-Godot([string[]]$GodotArgs, [int]$TimeoutSec = 120) {
    $out = [System.IO.Path]::GetTempFileName()
    $err = [System.IO.Path]::GetTempFileName()
    $p = Start-Process -FilePath $godot -ArgumentList $GodotArgs -NoNewWindow -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        Stop-Process -Id $p.Id -Force
        Remove-Item $out, $err
        return "TIMEOUT after $TimeoutSec s"
    }
    $text = (Get-Content $out -Raw) + (Get-Content $err -Raw)
    Remove-Item $out, $err
    return $text
}

function Report([string]$name, [bool]$ok, [string]$detail = "") {
    if ($ok) { Write-Host ("  OK    " + $name) -ForegroundColor Green }
    else { Write-Host ("  FAIL  " + $name + "  " + $detail) -ForegroundColor Red; $script:fail++ }
}

Write-Host "1. parse check"
$scripts = git ls-files "scripts/*.gd" "tests/*.gd"
foreach ($s in $scripts) {
    $r = Run-Godot @("--headless", "--path", ".", "--check-only", "--script", "res://$s") 60
    if ($r -match "(?i)error|TIMEOUT") { Report $s $false (($r -split "`n" | Select-String -Pattern "(?i)error|TIMEOUT" | Select-Object -First 2) -join " ") }
}
Report ("{0} scripts" -f $scripts.Count) ($fail -eq 0)
if ($fail -gt 0) {
    # a script that does not parse makes Godot hang on a black window: running the tests now only wastes time
    Write-Host "$fail CHECK(S) FAILED (parse errors: tests not run)" -ForegroundColor Red
    exit 1
}

Write-Host "2. tests"
$r = Run-Godot @("--headless", "--path", ".", "--script", "res://tests/save_test.gd") 300
Report "save round trip" ($r -match "SAVE TEST PASSED")
$r = Run-Godot @("--headless", "--path", ".", "--script", "res://tests/migration_test.gd") 300
Report "older save formats load and play on identically" ($r -match "MIGRATION TEST PASSED")
$r = Run-Godot @("--headless", "--path", ".", "--script", "res://tests/reach_test.gd") 300
Report "ants reach food walled by stones" ($r -match "reached 8/8")
$r = Run-Godot @("--headless", "--path", ".", "--script", "res://tests/enemy_test.gd") 300
Report "released enemies come in and are fought" ($r -match "ENEMY TEST PASSED")
$sandbox = Join-Path $env:APPDATA "Godot\app_userdata\AntFarm\sandbox\saves\slot1.antfarm"
if (Test-Path $sandbox) {
    $r = Run-Godot @("--headless", "--path", ".", "--script", "res://tests/real_save_test.gd") 300
    Report "keeper's colony loads and runs (sandbox copy)" ($r -match "fingerprint:")
}

Write-Host "3. determinism"
$base = "tests/baselines/selftest_w14_s5.txt"
$r = Run-Godot @("--headless", "--path", ".", "--", "--selftest=25", "--workers=14", "--seed=5", "--every=5") 600
# keep the colony numbers, drop the timing columns
$lines = $r -split "`n" | Where-Object { $_ -match "^\s+\d+\s|^nest:|queen alive" } |
    ForEach-Object { ($_ -replace "\s+\d+\s*$", "" -replace "sim time.*", "").TrimEnd() }
$now = ($lines -join "`n")
if ($UpdateBaseline -or -not (Test-Path $base)) {
    New-Item -ItemType Directory -Force (Split-Path $base) | Out-Null
    Set-Content -Path $base -Value $now -Encoding utf8
    Write-Host "  baseline written: $base" -ForegroundColor Yellow
} else {
    $was = (Get-Content $base -Raw).Trim() -replace "`r", ""
    Report "25-day self-test matches the baseline" ($was -eq $now.Trim()) "(intended change? rerun with -UpdateBaseline)"
}

if (-not $Quick) {
    Write-Host "4. speed (300 workers)"
    foreach ($v in @("outworld", "nest")) {
        $r = Run-Godot @("--path", ".", "--", "--shot=shots/check_$v.png", "--workers=300", "--seed=3", "--warm=0.3",
            "--tod=0.5", "--view=$v", "--live", "--frames=400") 300
        $fps = if ($r -match "fps (\d+)") { [int]$Matches[1] } else { 0 }
        Report ("{0} view: {1} fps (editor build; the exe runs faster; at least 45)" -f $v, $fps) ($fps -ge 45)   # (v0.8.51: raised from 25 to catch slow drift)
    }
}

if ($fail -eq 0) { Write-Host "ALL CHECKS PASSED" -ForegroundColor Green; exit 0 }
Write-Host "$fail CHECK(S) FAILED" -ForegroundColor Red
exit 1
