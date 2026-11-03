# Runs as the logged-in user. Installs kiro-cli (if missing) and copies the framework checkout from the share. Usage: user-setup.ps1 [-Src Y:\fw-src]
param([string]$Src = 'Y:\fw-src', [string]$Dst = "$env:USERPROFILE\fw-src")
$env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User')
if (-not (Get-Command kiro-cli -ErrorAction SilentlyContinue)) { irm 'https://cli.kiro.dev/install.ps1' | iex; $env:PATH += ";$env:LOCALAPPDATA\Kiro-Cli" }
if (Test-Path $Src) { robocopy $Src $Dst /MIR /XD .git coverage evals .wt /NFL /NDL /NJH /NP | Out-Null; Write-Host "framework -> $Dst ($(@(Get-ChildItem $Dst -ErrorAction SilentlyContinue).Count) entries)" }
$k = (Get-Command kiro-cli -ErrorAction SilentlyContinue).Source
if ($k) { $p = Start-Process $k -ArgumentList '--version' -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\kv.txt"; Write-Host "kiro-cli exit=$($p.ExitCode) $(Get-Content $env:TEMP\kv.txt -Raw)" ; if ($p.ExitCode -eq -1073741515) { Write-Host 'kiro-cli: 0xC0000135 DLL missing -> run win.sh bootstrap (VC++ runtime)' } }
Write-Host "node: $(node --version 2>$null)  git: $(git --version 2>$null)"
