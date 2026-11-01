# Setup of a VM built by `win.sh create`, run as SYSTEM by SetupComplete.cmd before the first logon:
# VMware Tools (vmrun guest ops need it), no sleep, private network. Log: C:\Users\Public\firstlogon.log.
$log = 'C:\Users\Public\firstlogon.log'
function Log($m) { Add-Content -Path $log -Value ("{0:HH:mm:ss} {1}" -f (Get-Date), $m) }
Log 'start'
$tools = Get-PSDrive -PSProvider FileSystem | Where-Object { (Test-Path ($_.Root + 'setup.exe')) -and (Test-Path ($_.Root + 'autorun.inf')) } | Select-Object -First 1
if ($tools) {
  Log "VMware Tools from $($tools.Root)"
  $p = Start-Process -FilePath ($tools.Root + 'setup.exe') -ArgumentList '/S /v"/qn REBOOT=R"' -Wait -PassThru
  Log "tools exit $($p.ExitCode)"
} else { Log 'no VMware Tools CD found' }
powercfg /change standby-timeout-ac 0; powercfg /change monitor-timeout-ac 0; powercfg /hibernate off
Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue
net accounts /maxpwage:unlimited | Out-Null
# test VM only: admins elevate without a consent prompt, so `win.sh sys` can reach SYSTEM unattended
reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v ConsentPromptBehaviorAdmin /t REG_DWORD /d 0 /f | Out-Null
Log 'done'
