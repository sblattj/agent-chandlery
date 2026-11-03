# Visibility smoke: prove the agent CLI runs headless in the VM and answers. Usage: pong.ps1 [-Agent my-agent] [-Dir <repo>]
param([string]$Agent = '', [string]$Dir = "$env:USERPROFILE")
$env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User')
Set-Location $Dir
Write-Host "--- $(kiro-cli --version) | node $(node --version) | $([Environment]::OSVersion.VersionString)"
Write-Host "--- whoami: $((kiro-cli whoami 2>&1 | Out-String).Trim() -replace "`r?`n",' / ')"
Write-Host '--- agent list'; kiro-cli agent list 2>&1 | Out-String | Write-Host
$a = @('chat','--no-interactive','--trust-all-tools'); if ($Agent) { $a += @('--agent',$Agent) }
Write-Host "--- pong ($(if ($Agent) {$Agent} else {'default agent'}))"
& kiro-cli @a 'Reply with exactly: pong' 2>&1 | Out-String | Write-Host
Write-Host "--- exit=$LASTEXITCODE"
