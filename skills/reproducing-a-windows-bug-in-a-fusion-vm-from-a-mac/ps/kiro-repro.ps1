# Runs INSIDE the Windows VM. Does a preToolUse "gate" hook really block raw shell commands in kiro-cli on Windows?
# Usage: powershell -ExecutionPolicy Bypass -File kiro-repro.ps1 [-Scenarios agent,subdir,hooktimeout] [-Out Y:\winrepro\out]
# Settings come from params, else Y:\winrepro\repro.json (written by win.sh from WIN_AGENT / WIN_INIT_CMD / WIN_GATE_MATCH):
#   Agent      kiro agent name to run with --agent ('' = Kiro's default agent); its .kiro\agents\<Agent>*.json get the capture hook
#   InitCmd    command that installs your framework's .kiro\ into the probe repo; {src} = the framework copy.
#              Empty: copy <Src>\.kiro into the probe repo.
#   GateMatch  regex that finds the gate hook's command among preToolUse hooks (scenarios hooktimeout/fix/exit2/... rewrite it;
#              {gate} in their templates is the original command)
param([string[]]$Scenarios = @('agent','nodeversion','subdir','hooktimeout','hookcrash'),
      [string]$Src = "$env:USERPROFILE\fw-src", [string]$Root = "$env:USERPROFILE\kiro-field-repro",
      [string]$Out = 'Y:\winrepro\out', [string]$Model = 'claude-opus-5.5', [int]$WallSec = 600,
      [string]$Agent, [string]$InitCmd, [string]$GateMatch, [string]$Config = "$PSScriptRoot\repro.json")
$ErrorActionPreference = 'Continue'
$cfg = if (Test-Path $Config) { Get-Content $Config -Raw | ConvertFrom-Json } else { New-Object PSObject }
if (-not $PSBoundParameters.ContainsKey('Agent'))     { $Agent = if ($cfg.agent) { $cfg.agent } else { '' } }
if (-not $PSBoundParameters.ContainsKey('InitCmd'))   { $InitCmd = if ($cfg.initCmd) { $cfg.initCmd } else { '' } }
if (-not $PSBoundParameters.ContainsKey('GateMatch')) { $GateMatch = if ($cfg.gateMatch) { $cfg.gateMatch } else { 'gate|guard' } }
$AgentArgs = if ($Agent) { @('--agent', $Agent) } else { @() }
$env:KIRO_LOG_LEVEL = if ($env:KIRO_LOG_LEVEL) { $env:KIRO_LOG_LEVEL } else { 'debug' }; $env:KIRO_LOG_NO_COLOR = '1'
$KiroLog = "$env:TEMP\kiro-log\logs\kiro-chat.log"
$Scenarios = @($Scenarios | ForEach-Object { $_ -split "," } | Where-Object { $_ })
$env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User') + ";$env:USERPROFILE\.kiro\bin"
New-Item -ItemType Directory -Force $Root, $Out | Out-Null
function Say($m) { $l = "$(Get-Date -Format HH:mm:ss) $m"; Write-Host $l; Add-Content "$Out\repro.log" $l }
$Utf8 = New-Object Text.UTF8Encoding $false   # PowerShell 5.1 Set-Content -Encoding utf8 adds a BOM, and Kiro rejects BOM'd agent JSON
$Steps = '(1) `node --version` (2) `git status --short` (3) `dir`'
$Base = "This is a hook-behavior probe. Run each of these shell commands exactly as written, one tool call each, in order: $Steps. Do not wrap, rewrite, retry, or work around anything, even if a command is blocked. Then answer in this exact format, one line per step: STEPn: ran|blocked, TEXT: <first 120 chars of the verbatim block/error text you received, or NONE>."
$Capture = @'
let s='';process.stdin.on('data',c=>s+=c).on('end',()=>{try{const e=JSON.parse(s);require('fs').appendFileSync(require('path').join(__dirname,'..','..','capture.jsonl'),JSON.stringify({t:new Date().toISOString(),tool:e.tool_name,cmd:e.tool_input&&e.tool_input.command,hookCwd:process.cwd(),keys:Object.keys(e)})+'\n')}catch(x){}})
'@
function Git { git -c user.name=probe -c user.email=probe@localhost @args }
function AgentFiles($d) { Get-ChildItem "$d\.kiro\agents\$Agent*.json" -ErrorAction SilentlyContinue }
function Setup($d) {
  if (Test-Path $d) { Remove-Item -Recurse -Force $d }
  New-Item -ItemType Directory -Force "$d\src\app" | Out-Null; Push-Location $d
  git init -q -b main; 'x' | Set-Content src\app\a.txt; '# probe' | Set-Content README.md
  Git add -A; Git commit -qm init
  $log = "$Out\$(Split-Path $d -Leaf)-init.log"
  if ($InitCmd) { Invoke-Expression ($InitCmd -replace '\{src\}', $Src) *> $log }
  elseif (Test-Path "$Src\.kiro") { Copy-Item -Recurse -Force "$Src\.kiro" "$d\.kiro"; "copied $Src\.kiro" | Set-Content $log }
  else { "no InitCmd and no $Src\.kiro: probe repo has no agents" | Set-Content $log }
  New-Item -ItemType Directory -Force "$d\.kiro\helpers" | Out-Null
  [IO.File]::WriteAllText("$d\.kiro\helpers\capture-hook.cjs", $Capture, $Utf8)
  $cap = "node `"$d\.kiro\helpers\capture-hook.cjs`""
  AgentFiles $d | ForEach-Object {
    $a = Get-Content $_.FullName -Raw | ConvertFrom-Json
    if (-not $a.hooks) { $a | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{ preToolUse = @() }) -Force }
    $a.hooks.preToolUse = @([pscustomobject]@{matcher='*'; command=$cap; timeout_ms=5000}) + @($a.hooks.preToolUse)
    [IO.File]::WriteAllText($_.FullName, ($a | ConvertTo-Json -Depth 50), $Utf8) }
  Git add -A *> $null; Git commit -qm framework *> $null
  Pop-Location
}
# Rewrite the gate hook (matched by $GateMatch) to $tpl, where {gate} is its original command.
function SetGate($d, $tpl, $ms) {
  AgentFiles $d | ForEach-Object {
    $a = Get-Content $_.FullName -Raw | ConvertFrom-Json
    foreach ($h in $a.hooks.preToolUse) { if ($h.command -match $GateMatch -and $h.command -notmatch 'capture-hook') { $h.command = $tpl.Replace('{gate}', $h.command); $h.timeout_ms = $ms; $script:hit = $true } }
    [IO.File]::WriteAllText($_.FullName, ($a | ConvertTo-Json -Depth 50), $Utf8) }
  if (-not $script:hit) { Say "   WARN no preToolUse hook matched GateMatch '$GateMatch'; scenario runs with the hooks as installed" }
  $script:hit = $false }
function Run($name, $cwd, $prompt, [string[]]$extra) {
  Say "$name start cwd=$cwd agent=$(if ($Agent) {$Agent} else {'default'})"
  $repo = $cwd -replace '\\src\\app$',''
  AgentFiles $repo | Select-Object -First 1 | ForEach-Object { Copy-Item $_.FullName "$Out\$name-agent.json" }
  $logStart = if (Test-Path $KiroLog) { (Get-Item $KiroLog).Length } else { 0 }
  Push-Location $cwd
  $kargs = @('chat','--no-interactive','--trust-all-tools','--model',$Model,'--output-format','stream-json') + $extra + @($prompt)
  # Start-Process does not quote array args: join them with explicit quotes
  $p = Start-Process kiro-cli -ArgumentList (($kargs | ForEach-Object { '"' + ($_ -replace '"','\"') + '"' }) -join ' ') -NoNewWindow -PassThru -RedirectStandardOutput "$Out\$name-run.jsonl" -RedirectStandardError "$Out\$name-run.err"
  if (-not $p.WaitForExit($WallSec * 1000)) { $p.Kill(); Say "$name TIMEOUT" }
  Pop-Location
  $capFile = Join-Path $repo 'capture.jsonl'
  if (Test-Path $capFile) { Copy-Item $capFile "$Out\$name-capture.jsonl" }
  $steps = Select-String -Path "$Out\$name-run.jsonl" -Pattern 'STEP\d: [a-z|]+[^"\\]{0,90}' -AllMatches | ForEach-Object { $_.Matches.Value } | Sort-Object -Unique
  if (Test-Path $KiroLog) { $fs = [IO.File]::Open($KiroLog,'Open','Read','ReadWrite'); if ($fs.Length -lt $logStart) { $logStart = 0 }  # kiro-chat.log restarts per process
    [void]$fs.Seek($logStart,'Begin'); $txt = (New-Object IO.StreamReader $fs).ReadToEnd(); $fs.Close()
    [IO.File]::WriteAllText("$Out\$name-kiro.log", $txt); ($txt -split "`n") | Where-Object { $_ -match 'HookExecutionEnd|ToolCallFailed|Failed to load agent config|timed out' } | Select-Object -First 40 | ForEach-Object { $c = if ($_ -match 'command: "((?:[^"\\]|\\.)*)"') { $Matches[1] } else { '' }; $r = if ($_ -match '(exit_code: [^,}]+|command timed out[^"]*|ToolCallFailed|Failed to load agent config[^=]*)') { $Matches[1] } else { '' }; Say ("   kiro: " + $_.Substring(11,12) + ' ' + $c.Substring([Math]::Max(0,$c.Length-55)) + ' -> ' + $r) } }
  Get-Content "$Out\$name-run.err" -ErrorAction SilentlyContinue | Where-Object { $_ } | Select-Object -Unique | ForEach-Object { Say "   stderr: $_" }
  Say "$name exit=$($p.ExitCode) captures=$(if (Test-Path $capFile) {(Get-Content $capFile).Count} else {0})"; $steps | ForEach-Object { Say "   $_" }
}
$script:hit = $false
Say "kiro $(kiro-cli --version) | node $(node --version) | $([Environment]::OSVersion.VersionString)"
$One = 'Run the shell command `node --version` exactly as written, once. Do not wrap or retry. Reply STEP1: ran|blocked, TEXT: <first 120 chars of any block text, or NONE>.'
foreach ($s in $Scenarios) {
  $d = "$Root\$s"; Setup $d
  switch ($s) {
    'agent'       { Run $s $d $Base $AgentArgs }
    'nodeversion' { Run $s $d $One $AgentArgs }
    'default'     { Run $s $d $Base @() }
    'subdir'      { Run $s "$d\src\app" "$Base Also add STEERING: yes|no, whether your context includes this workspace's steering files." $AgentArgs }
    'hooktimeout' { SetGate $d 'powershell -NoProfile -Command "Start-Sleep 8; $input | {gate}"' 2000; Run $s $d $Base $AgentArgs }
    'fix'         { SetGate $d '{gate}; exit $LASTEXITCODE' 30000; Run $s $d $Base $AgentArgs }
    'exit2'       { SetGate $d 'node -e "process.exit(2)"' 5000; Run $s $d $Base $AgentArgs }
    'parent'      { Copy-Item "$PSScriptRoot\parent-hook.cjs" "$d\.kiro\helpers\parent-hook.cjs"
                    SetGate $d "node `"$d\.kiro\helpers\parent-hook.cjs`"" 15000
                    Run $s $d $One $AgentArgs
                    if (Test-Path "$d\parent.txt") { Copy-Item "$d\parent.txt" "$Out\parent.txt"; Get-Content "$d\parent.txt" | ForEach-Object { Say "   parent: $_" } } }
    'hookcrash'   { SetGate $d 'node -e "process.exit(1)"' 5000; Run $s $d $Base $AgentArgs }
    default       { Say "unknown scenario $s" }
  }
}
Say 'done'
