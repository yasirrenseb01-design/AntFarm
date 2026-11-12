# Runs every check before a release (see docs/WORKFLOW.md):
#   1. parse-check every script (a script with a parse error would hang the game, so this goes first)
#   1b. file sizes: code over ~500 lines fails (older big files: tools/size_allow.txt); big docs warn
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

Write-Host "1b. file sizes (docs/WORKFLOW.md)"
# code: over ~500 lines is split; the files that were already over on 2026-11-08 are in tools/size_allow.txt with
# their line count then - they may shrink, not grow. A new file over 500 fails too.
$allow = @{}
Get-Content "tools/size_allow.txt" -Encoding utf8 | Where-Object { $_ -match '^(\d+) (.+)$' } | ForEach-Object { $allow[$Matches[2]] = [int]$Matches[1] }
$sizeFail = 0
foreach ($f in (git ls-files "*.gd" "*.py" "*.gdshader" "*.cpp" "*.h" "*.ps1" "*.sh")) {
    $n = @(Get-Content $f -Encoding utf8).Count
    if ($allow.ContainsKey($f)) {
        if ($n -gt $allow[$f]) { Report $f $false ("{0} lines, was {1}: split it or move code out (tools/size_allow.txt)" -f $n, $allow[$f]); $sizeFail++ }
        elseif ($n -le 500) { Write-Host ("  NOTE  {0} is {1} lines now: take it out of tools/size_allow.txt" -f $f, $n) -ForegroundColor Yellow }
    } elseif ($n -gt 500) { Report $f $false ("{0} lines (over 500): split it (tools/dev/split_gd.py)" -f $n); $sizeFail++ }
}
Report ("code files: none over 500 lines, none of the {0} older big ones grown" -f $allow.Count) ($sizeFail -eq 0)
# docs that every session reads: a warning only (they are split by hand, see WORKFLOW "เอกสารที่โตได้")
foreach ($d in @(@("CHANGELOG.md", 600), @("docs/roadmap/BACKLOG.md", 300), @("docs/LESSONS.md", 120))) {
    $n = @(Get-Content $d[0] -Encoding utf8).Count
    if ($n -gt $d[1]) { Write-Host ("  WARN  {0}: {1} lines (over {2}) - split it (docs/WORKFLOW.md)" -f $d[0], $n, $d[1]) -ForegroundColor Yellow }
}

Write-Host "2. tests"
$r = Run-Godot @("--headless", "--path", ".", "--script", "res://tests/save_test.gd") 300
Report "save round trip" ($r -match "SAVE TEST PASSED")
$r = Run-Godot @("--headless", "--path", ".", "--script", "res://tests/migration_test.gd") 300
Report "older save formats load and play on identically" ($r -match "MIGRATION TEST PASSED")
$cropArgs = @("--headless", "--path", ".", "--script", "res://tests/crop_ledger_test.gd")
if (-not $Quick) { $cropArgs += @("--", "long") }          # (quick: ~30 s; long: three colonies for 100 days, ~5 min)
$r = Run-Godot $cropArgs 1500
Report "workers' crops and fat: their sums are the colony's sugar and fat, nothing made or lost, honeydew flows full to empty" ($r -match "CROP LEDGER TEST PASSED")
$r = Run-Godot @("--headless", "--path", ".", "--script", "res://tests/reach_test.gd") 300
Report "ants reach food walled by stones" ($r -match "reached 8/8")
$r = Run-Godot @("--headless", "--path", ".", "--script", "res://tests/enemy_test.gd") 300
Report "released enemies come in and are fought" ($r -match "ENEMY TEST PASSED")
$r = Run-Godot @("--headless", "--path", ".", "--script", "res://tests/name_test.gd") 300
Report "ant names kept, change nothing, a named death is told" ($r -match "NAME TEST PASSED")
$r = Run-Godot @("--headless", "--path", ".", "--script", "res://tests/stats_test.gd") 300
Report "statistics: saved chart sets read back, a hand-changed file taken safely" ($r -match "STATS TEST PASSED")
$r = Run-Godot @("--headless", "--path", ".", "--script", "res://tests/water_test.gd") 300
Report "water tanks: filled from the Home, the helper, Colony Harmony for a filling" ($r -match "WATER TEST PASSED")
$r = Run-Godot @("--headless", "--path", ".", "--script", "res://tests/lang_test.gd") 300
Report "words: every key in both languages, same placeholders, no Thai left in the code" ($r -match "LANG TEST PASSED")
$r = Run-Godot @("--headless", "--path", ".", "--script", "res://tests/duty_test.gd") 300
Report "duties in the nest: repeatable, counted, run while closed" ($r -match "DUTY TEST PASSED")
$r = Run-Godot @("--headless", "--path", ".", "--script", "res://tests/save_fuzz_test.gd") 300
Report "broken or changed saves, settings and port messages: no code run, no hang, no script error" ($r -match "SAVE FUZZ TEST PASSED")
$saveFilesArgs = @("--headless", "--path", ".", "--script", "res://tests/save_files_test.gd")
if (-not $Quick) { $saveFilesArgs += @("--", "big") }      # (+ a nest of the most soil a save may hold: ~7 s)
$r = Run-Godot $saveFilesArgs 300
Report "saves, slotN.json, harmony.json, home.json cut off mid-write: the last good copy read, never written over$(if (-not $Quick) { ', the biggest nest saved and read back' })" ($r -match "SAVE FILES TEST PASSED")
$r = Run-Godot @("--headless", "--path", ".", "--script", "res://tests/dump_test.gd") 300
Report "the diggers carry their soil out themselves (laying a trail, back in)" ($r -match "DUMP TEST PASSED")
$r = Run-Godot @("--headless", "--path", ".", "--script", "res://tests/species_test.gd") 120
Report "every species has every key (scripts/sim/species/registry.gd)" ($r -match "SPECIES TEST PASSED")
$r = Run-Godot @("--headless", "--path", ".", "--script", "res://tests/files_fuzz_test.gd") 300
Report "harmony.json, home.json and the tanks' pictures broken or changed: no script error, a huge picture not decoded" ($r -match "FILES FUZZ TEST PASSED" -and $r -notmatch "SCRIPT ERROR")
$r = Run-Godot @("--headless", "--path", ".", "--script", "res://tests/native_guard_test.gd") 120
Report "the C++ part given wrong sizes: answers air, reads nothing past its arrays" ($r -match "NATIVE GUARD TEST PASSED")
$r = Run-Godot @("--headless", "--path", ".", "--script", "res://tests/tank_spec_test.gd") 120
Report "the tank's sizes: one set, the same as the simulation's" ($r -match "TANK SPEC TEST PASSED")
$r = Run-Godot @("--headless", "--path", ".", "--script", "res://tests/home_test.gd") 120
Report "the Home's tanks and the wild mode's slots: the keeper's saves kept, hidden ones taken back" ($r -match "HOME TEST PASSED")
$r = Run-Godot @("--headless", "--path", ".", "--script", "res://tests/work_left_test.gd") 300
Report "the daily count of the work left: the same as the plain way" ($r -match "WORK LEFT PASSED")
# the keeper's own saves (read only): each still passes the loading checks - else the game would give it up as unreadable
$r = Run-Godot @("--headless", "--path", ".", "--script", "res://tests/real_saves_check.gd") 300
Report "the keeper's own saves would all load (read only)" ($r -match "REAL SAVES CHECK PASSED")
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
            "--tod=0.5", "--view=$v", "--live", "--frames=400", "--no-xray") 300
        $fps = if ($r -match "fps (\d+)") { [int]$Matches[1] } else { 0 }
        Report ("{0} view: {1} fps (editor build on the Intel UHD; the exe runs faster; at least 40)" -f $v, $fps) ($fps -ge 40)   # (v0.8.51: raised from 25 to catch slow drift; v0.11.15: 40 - the editor draws on the integrated Intel UHD, where the nest at 300 ants is CPU-bound and swings 42-47 run to run)
    }
    # the nest seen through the soil (how it opens from v0.11.79): every nestmate on screen at once - 120 workers (the
    # keeper's own colonies are 100-250); at 300 it is ~19 fps here (BACKLOG)
    $r = Run-Godot @("--path", ".", "--", "--shot=shots/check_xray.png", "--workers=120", "--seed=3", "--warm=0.3",
        "--tod=0.5", "--view=nest", "--live", "--frames=400") 300
    $fps = if ($r -match "fps (\d+)") { [int]$Matches[1] } else { 0 }
    Report ("nest through the soil, 120 workers: {0} fps (at least 40)" -f $fps) ($fps -ge 40)
}

if ($fail -eq 0) { Write-Host "ALL CHECKS PASSED" -ForegroundColor Green; exit 0 }
Write-Host "$fail CHECK(S) FAILED" -ForegroundColor Red
exit 1
