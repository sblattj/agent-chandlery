# Runs as the user: disable VS Code workspace trust in Kiro's user settings (test VM only) so hooks/agents run without the trust dialog.
$p = "$env:APPDATA\Kiro\User\settings.json"
New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null
$j = if (Test-Path $p) { Get-Content $p -Raw | ConvertFrom-Json } else { New-Object PSObject }
if (-not $j) { $j = New-Object PSObject }
$j | Add-Member -NotePropertyName 'security.workspace.trust.enabled' -NotePropertyValue $false -Force
[IO.File]::WriteAllText($p, ($j | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding $false))
Get-Content $p
