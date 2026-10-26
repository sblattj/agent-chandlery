# Runs as the user: start Kiro IDE on the interactive desktop with CDP on 127.0.0.1:9222.
param([string]$Workspace = 'C:\Users\Public\kiro-ide-ws', [int]$Port = 9222)
New-Item -ItemType Directory -Force $Workspace | Out-Null
$exe = "$env:LOCALAPPDATA\Programs\Kiro\Kiro.exe"
Get-Process Kiro -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 2
$cmd = "`"$exe`" --remote-debugging-port=$Port `"$Workspace`""
schtasks /Delete /TN KiroIDE-CDP /F 2>$null | Out-Null
schtasks /Create /TN KiroIDE-CDP /TR $cmd /SC ONCE /ST 23:59 /IT /F | Out-Null
schtasks /Run /TN KiroIDE-CDP | Out-Null
for ($i = 0; $i -lt 30; $i++) {
  try { $v = Invoke-RestMethod "http://127.0.0.1:$Port/json/version" -TimeoutSec 2; "CDP up: $($v.Browser)"; break } catch { Start-Sleep 1 }
}
if (-not $v) { 'CDP did not come up in 30s' }
Get-Process Kiro -ErrorAction SilentlyContinue | Select-Object -First 1 Id,SessionId | Format-Table -AutoSize
