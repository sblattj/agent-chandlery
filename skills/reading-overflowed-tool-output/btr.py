#!/usr/bin/env -S python3 -I
"""btr.py: find and read persisted tool results that were too big for the context.
Where they land (Claude Code on macOS/Linux; TMP = realpath of $BTR_TMP, else of /tmp):
  MCP / Bash overflow:  ~/.claude/projects/<cwd-slug>/<session-id>/tool-results/<tool>-<ts>.txt   ("result ... exceeds maximum allowed tokens" / "<persisted-output>")
  Workflow task output: TMP/claude-<uid>/<cwd-slug>/<session-id>/tasks/<taskId>.output  (json wrapper: summary, logs, result)
usage:
  btr.py ls [--sid ID] [-n 15]                      newest persisted results + task outputs (size, kind, first line)
  btr.py show FILE [--keys] [--path a.b[0].c] [--head N] [--grep REGEX] [--len]
      JSON files: --keys lists top-level keys (after unwrapping {"result":...}); --path walks into it; --len prints lengths.
      Text files: --head / --grep. The <persisted-output> preview wrapper is stripped automatically.
  btr.py task TASKID [--path ...]                   same as show on the newest tasks/<TASKID>.output
"""
import glob, json, os, re, sys
H = os.path.expanduser('~')
CFG = os.path.expanduser(os.environ.get('CLAUDE_CONFIG_DIR') or '~/.claude')
TMPS = [os.path.realpath(os.environ.get('BTR_TMP') or '/tmp')]  # /tmp resolves to /private/tmp on macOS
def sessions(sid=None):
    pat = f"{CFG}/projects/*/{sid or '*'}/"
    return sorted((d for d in glob.glob(pat) if os.path.isdir(d)), key=os.path.getmtime, reverse=True)
def find_files(sid=None):
    out = []
    for d in sessions(sid)[: (1 if not sid else 50)]:
        s = os.path.basename(d.rstrip('/')); slug = os.path.basename(os.path.dirname(d.rstrip('/')))
        out += glob.glob(f"{d}tool-results/*")
        for tmp in TMPS: out += glob.glob(f"{tmp}/claude-*/{slug}/{s}/tasks/*.output")
    return sorted(set(out), key=os.path.getmtime, reverse=True)
def unwrap_text(t):
    m = re.search(r'Full output saved to: (\S+)', t)
    if t.startswith('<persisted-output>') and m and os.path.exists(m.group(1)): return open(m.group(1), errors='ignore').read()
    return t
def load(path):
    t = unwrap_text(open(path, errors='ignore').read())
    try:
        j = json.loads(t)
        if isinstance(j, dict) and 'result' in j and ('summary' in j or 'logs' in j): j = j['result']  # workflow task wrapper
        return j, t
    except Exception: return None, t
def walk(j, path):
    for tok in re.findall(r'[^.\[\]]+|\[\d+\]', path or ''):
        j = j[int(tok[1:-1])] if tok.startswith('[') else j[tok]
    return j
def describe(j):
    if isinstance(j, dict): return 'dict{' + ', '.join(f"{k}:{describe_short(v)}" for k, v in list(j.items())[:30]) + '}'
    if isinstance(j, list): return f"list[{len(j)}]" + (f" of {describe_short(j[0])}" if j else '')
    return type(j).__name__
def describe_short(v):
    if isinstance(v, dict): return f"dict({len(v)})"
    if isinstance(v, list): return f"list[{len(v)}]"
    if isinstance(v, str): return f"str({len(v)})"
    return type(v).__name__
def cmd_ls(a):
    sid = a[a.index('--sid')+1] if '--sid' in a else None; n = int(a[a.index('-n')+1]) if '-n' in a else 15
    for f in find_files(sid)[:n]:
        j, t = load(f); kind = describe(j) if j is not None else 'text'
        first = t.strip().splitlines()[0][:80] if t.strip() else ''
        print(f"{os.path.getsize(f):>9,}  {kind[:60]:60}  {f}\n{'':11}{first}")
def cmd_show(f, a):
    j, t = load(f)
    if j is not None and ('--keys' in a or '--path' in a or '--len' in a):
        j = walk(j, a[a.index('--path')+1]) if '--path' in a else j
        if '--keys' in a or '--len' in a: print(describe(j)); return
        print(json.dumps(j, indent=1)[: int(a[a.index('--head')+1]) * 120 if '--head' in a else 20000]); return
    lines = t.splitlines()
    if '--grep' in a: rx = re.compile(a[a.index('--grep')+1], re.I); lines = [f"{i+1}:{l}" for i, l in enumerate(lines) if rx.search(l)]
    n = int(a[a.index('--head')+1]) if '--head' in a else 60
    print('\n'.join(lines[:n])); 
    if len(lines) > n: print(f"... {len(lines)-n} more lines ({len(t):,} chars total)")
def main(a):
    if not a or a[0] == 'ls': cmd_ls(a[1:])
    elif a[0] == 'show': cmd_show(a[1], a[2:])
    elif a[0] == 'task':
        fs = sorted({f for tmp in TMPS for f in glob.glob(f"{tmp}/claude-*/*/*/tasks/{a[1]}.output")}, key=os.path.getmtime, reverse=True)
        if not fs: sys.exit(f"no tasks/{a[1]}.output under {' or '.join(t + '/claude-*' for t in TMPS)}")
        print(fs[0]); cmd_show(fs[0], a[2:] or ['--keys'])
    else: print(__doc__)
if __name__ == '__main__': main(sys.argv[1:])
