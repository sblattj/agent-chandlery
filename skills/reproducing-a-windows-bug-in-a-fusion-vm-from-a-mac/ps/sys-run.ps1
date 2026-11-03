# Run a .ps1 as SYSTEM (installs without UAC) and print its output. vmrun has no SYSTEM mode, so this goes
# through a one-shot scheduled task. Needs an elevated caller (win.sh's guest user is an admin with no consent prompt).
# SYSTEM can't see the share, so the script is copied to C:\Users\Public first.
# Usage: sys-run.ps1 -File Y:\winrepro\x.ps1 [-ArgLine '-Mac 1.2.3.4'] [-TimeoutSec 1800]
param([Parameter(Mandatory)][string]$File, [string]$ArgLine = '', [int]$TimeoutSec = 1800)
$log = "C:\Users\Public\sys-run-$PID.log"; $name = "winrepro-sys-$PID"
Copy-Item $File C:\Users\Public\ -Force; $File = Join-Path C:\Users\Public (Split-Path $File -Leaf)
# /TR gets a quote-free wrapper path: PowerShell 5.1 mangles the embedded quotes of an inline command
$wrap = "C:\Users\Public\$name.cmd"
Set-Content $wrap "@powershell -NoProfile -ExecutionPolicy Bypass -Command `"& '$File' $ArgLine *> '$log'`"" -Encoding ASCII
schtasks /Create /TN $name /RU SYSTEM /RL HIGHEST /SC ONCE /ST 00:00 /F /TR $wrap | Out-Null
if ($LASTEXITCODE) { Write-Host "schtasks /Create failed ($LASTEXITCODE): is the caller elevated?"; exit 1 }
schtasks /Run /TN $name | Out-Null; $t0 = Get-Date
do { Start-Sleep 2; $st = (Get-ScheduledTask -TaskName $name).State } while ($st -eq 'Running' -and ((Get-Date) - $t0).TotalSeconds -lt $TimeoutSec)
$rc = (Get-ScheduledTaskInfo -TaskName $name).LastTaskResult
if (Test-Path $log) { Get-Content $log; Remove-Item $log -Force }
schtasks /Delete /TN $name /F | Out-Null; Remove-Item $wrap -Force -ErrorAction SilentlyContinue
if ($st -eq 'Running') { Write-Host "timed out after $TimeoutSec s"; exit 1 }
exit $rc
