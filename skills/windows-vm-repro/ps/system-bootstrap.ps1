# Runs as SYSTEM (no UAC). Fixes a fresh Windows VM: trusted roots, VC++ runtime, Node, Git, from installers staged in C:\Users\Public.
$ErrorActionPreference = 'Continue'; $P = 'C:\Users\Public'
certutil -generateSSTFromWU "$P\roots.sst" | Select-Object -Last 1
if (Test-Path "$P\roots.sst") { Write-Host ("roots imported: " + @(Get-ChildItem "$P\roots.sst" | Import-Certificate -CertStoreLocation Cert:\LocalMachine\Root).Count) }
$vc = Get-ChildItem "$P\vc_redist.*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($vc) { $p = Start-Process $vc.FullName -ArgumentList '/install /quiet /norestart' -Wait -PassThru; Write-Host "vc_redist exit=$($p.ExitCode)" }
if (-not (Test-Path 'C:\Program Files\nodejs\node.exe')) { $m = Get-ChildItem "$P\node-*.msi" | Select-Object -First 1; if ($m) { Start-Process msiexec -ArgumentList "/i `"$($m.FullName)`" /qn /norestart" -Wait; Write-Host "node installed from $($m.Name)" } }
if (-not (Test-Path 'C:\Program Files\Git\cmd\git.exe')) { $g = Get-ChildItem "$P\Git-*.exe" | Select-Object -First 1; if ($g) { Start-Process $g.FullName -ArgumentList '/VERYSILENT /NORESTART /SUPPRESSMSGBOXES' -Wait; Write-Host "git installed from $($g.Name)" } }
Write-Host "node=$(Test-Path 'C:\Program Files\nodejs\node.exe') git=$(Test-Path 'C:\Program Files\Git\cmd\git.exe')"
