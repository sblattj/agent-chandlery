#!/usr/bin/env python3
"""Per-hook verdicts from a Kiro debug log (KIRO_LOG_LEVEL=debug): start/end time, duration, exit code / timeout, tool outcome.
Usage: kiro-hook-verdicts.py <kiro-chat.log slice>"""
import re, sys, datetime as dt
ts = lambda l: dt.datetime.fromisoformat(l[:26].rstrip('Z'))
starts = {}
for line in open(sys.argv[1], encoding='utf-8', errors='replace'):
    if 'HookExecutionStart(' in line and 'agent::agent: 4569' in line or ('HookExecutionEnd(' in line and 'agent::agent: 4569' in line) or 'ToolCallFailed' in line or ('ToolCallFinished' in line):
        cmd = re.search(r'command: "((?:[^"\\]|\\.)*)"', line)
        c = (cmd.group(1) if cmd else '?')[-60:]
        if 'HookExecutionStart(' in line: starts[c] = ts(line); continue
        if 'HookExecutionEnd(' in line:
            res = re.search(r'(exit_code: [^,}]+|Timeout[^,}]*|timed_out: \w+|status: [^,}]+|Err\([^)]{0,80}\))', line)
            out = re.search(r'(stdout|output): "((?:[^"\\]|\\.){0,80})', line)
            d = (ts(line) - starts.get(c, ts(line))).total_seconds()
            print(f"{line[11:23]} HOOK {c:<60} {d:5.2f}s {res.group(1) if res else '?'} {('out=' + out.group(2)) if out else ''}")
        else:
            m = re.search(r'raw_input: Object \{"command": String\("((?:[^"\\]|\\.){0,60})', line)
            print(f"{line[11:23]} TOOL {'FAILED/BLOCKED' if 'ToolCallFailed' in line else 'finished'}: {m.group(1) if m else ''}")
