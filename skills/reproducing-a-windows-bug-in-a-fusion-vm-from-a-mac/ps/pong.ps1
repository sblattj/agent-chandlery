# Visibility smoke: prove the agent CLI runs headless in the VM and answers. Usage: pong.ps1 [-Agent my-agent] [-Dir <repo>] [-Model <id>]
# Always pass a model: a fresh Kiro home defaults to whatever Kiro picks, which may be a model you don't allow.
param([string]$Agent = '', [string]$Dir = "$env:USERPROFILE", [string]$Model = 'claude-sonnet-5.5')
$env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User')
Set-Location $Dir
Write-Host "--- $(kiro-cli --version) | node $(node --version) | $([Environment]::OSVersion.VersionString)"
Write-Host "--- whoami: $((kiro-cli whoami 2>&1 | Out-String).Trim() -replace "`r?`n",' / ')"
Write-Host '--- agent list'; kiro-cli agent list 2>&1 | Out-String | Write-Host
$a = @('chat','--no-interactive','--trust-all-tools','--model',$Model); if ($Agent) { $a += @('--agent',$Agent) }
Write-Host "--- pong ($(if ($Agent) {$Agent} else {'default agent'}))"
& kiro-cli @a 'Reply with exactly: pong' 2>&1 | Out-String | Write-Host
Write-Host "--- exit=$LASTEXITCODE"
