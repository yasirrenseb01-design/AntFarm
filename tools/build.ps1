# Builds the game: an archived copy per version in build\versions, then replaces build\AntFarm.exe
# (the file the desktop shortcut opens). If the game is open, a hidden helper waits for it to close
# and then swaps the new version in, so the shortcut always opens the latest build.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$godot = "E:\Godot_v4.7.2-stable_win64_console.exe"
$version = (Select-String -Path "$root\project.godot" -Pattern 'config/version="([^"]+)"').Matches[0].Groups[1].Value
$archived = "$root\build\versions\AntFarm-v$version.exe"
$target = "$root\build\AntFarm.exe"
New-Item -ItemType Directory -Force "$root\build\versions" | Out-Null
# desktop mode's Win32 helper (tools/desktop/antdesk.cs), next to the game and its archived versions: built with the C#
# compiler that comes with Windows (.NET Framework 4)
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
& $csc /nologo /target:winexe /platform:x64 /r:System.Drawing.dll /r:System.Windows.Forms.dll /out:"$root\build\AntDesk.exe" "$root\tools\desktop\antdesk.cs"
if ($LASTEXITCODE -ne 0) { throw "AntDesk.exe failed to build" }
try { Copy-Item "$root\build\AntDesk.exe" "$root\build\versions\AntDesk.exe" -Force } catch {}
& $godot --headless --path $root --export-release "Windows Desktop" $archived
if (-not (Test-Path $archived)) { throw "export failed" }
try {
    Copy-Item $archived $target -Force
    Write-Output "built v$version -> $target"
} catch {
    $cmd = "Wait-Process -Name AntFarm -ErrorAction SilentlyContinue; Start-Sleep -Seconds 1; Copy-Item '$archived' '$target' -Force"
    Start-Process powershell -WindowStyle Hidden -ArgumentList "-NoProfile", "-Command", $cmd
    Write-Output "built v$version -> $archived (game is open: the shortcut switches to v$version as soon as it is closed)"
}

# Old builds: keep the five newest and the first build of every PART (x.y.0); remove the rest.
$all = Get-ChildItem "$root\build\versions" -Filter "AntFarm-v*.exe" | ForEach-Object {
    $v = $_.BaseName -replace '^AntFarm-v', ''
    [pscustomobject]@{ File = $_; Ver = [version]$v; Patch = [int]($v.Split('.')[2]) }
} | Sort-Object Ver -Descending
$keep = @($all | Select-Object -First 5) + @($all | Where-Object { $_.Patch -eq 0 })
foreach ($b in $all) {
    if ($keep.File.FullName -notcontains $b.File.FullName) {
        try { Remove-Item $b.File.FullName -ErrorAction Stop; Write-Output "removed old build $($b.File.Name)" } catch {}
    }
}
