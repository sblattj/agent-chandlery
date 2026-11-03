// Diagnostic preToolUse hook: record the process chain that launched it, then exit 2 (block).
const { execSync } = require('child_process');
let s = '';
process.stdin.on('data', (c) => (s += c)).on('end', () => {
  const chain = []; let pid = process.ppid;
  for (let i = 0; i < 4 && pid; i++) {
    try {
      const o = execSync(`powershell -NoProfile -Command "$p = Get-CimInstance Win32_Process -Filter ProcessId=${pid}; [string]$p.ParentProcessId + '|' + $p.CommandLine"`).toString().trim();
      const at = o.indexOf('|'); chain.push(`${pid}: ${o.slice(at + 1)}`); pid = +o.slice(0, at);
    } catch (e) { chain.push(`${pid}: <lookup failed>`); break; }
  }
  require('fs').appendFileSync(require('path').join(__dirname, '..', '..', 'parent.txt'), chain.join('\n') + '\n---\n');
  process.stderr.write('[parent-hook: blocked for diagnosis]\n');
  process.exit(2);
});
