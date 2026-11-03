# FIRED/absent for a test hook that writes a marker file into the workspace. Usage: marker.ps1 -Dir <ws> [-Name .hook-fired]
param([string]$Dir, [string]$Name = '.hook-fired')
$f = Join-Path $Dir $Name
if (Test-Path $f) { "marker: FIRED"; Get-Content $f } else { "marker: absent" }
