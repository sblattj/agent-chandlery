# Runs as the user: silent-install the Kiro IDE installer staged on the share (win.sh ide install downloads it on the Mac).
$ErrorActionPreference = 'Stop'
Copy-Item Y:\winrepro\kiro-ide.exe $env:TEMP\kiro-ide.exe -Force
$sig = Get-AuthenticodeSignature $env:TEMP\kiro-ide.exe
"signature: $($sig.Status) $($sig.SignerCertificate.Subject.Split(',')[0])"
if ($sig.Status -ne 'Valid') { throw 'installer signature is not valid; not running it' }
$p = Start-Process $env:TEMP\kiro-ide.exe -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/MERGETASKS=!runcode' -Wait -PassThru
"installer exit: $($p.ExitCode)"
"Kiro.exe present: $(Test-Path "$env:LOCALAPPDATA\Programs\Kiro\Kiro.exe")"
