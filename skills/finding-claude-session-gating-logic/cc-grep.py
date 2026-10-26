#!/usr/bin/env python3
"""Search the installed Claude Code binary's JS for a string or function and print context.

Usage:
  cc-grep.py 'Cannot background'            # context around every hit (default 400 before / 200 after)
  cc-grep.py -f Fa                          # body of every `function Fa(){...}` (minified names repeat across bundles)
  cc-grep.py -b 800 -a 300 'some message'   # wider context
Env: CLAUDE_BIN overrides the binary (default: newest ~/.local/share/claude/versions/*).
"""
import argparse, glob, os, re, subprocess, sys

ap = argparse.ArgumentParser()
ap.add_argument("pattern")
ap.add_argument("-f", "--function", action="store_true", help="treat pattern as a minified function name")
ap.add_argument("-b", type=int, default=400)
ap.add_argument("-a", type=int, default=200)
ap.add_argument("-n", type=int, default=5, help="max hits")
o = ap.parse_args()

binp = os.environ.get("CLAUDE_BIN") or max(glob.glob(os.path.expanduser("~/.local/share/claude/versions/*")), key=os.path.getmtime)
if os.path.isdir(binp):
    binp = max(glob.glob(binp + "/*"), key=os.path.getmtime)
cache = f"/tmp/cc-strings-{os.path.basename(binp)}.txt"
if not os.path.exists(cache):
    with open(cache, "w") as fh:
        subprocess.run(["strings", binp], stdout=fh, check=True)
s = open(cache, errors="ignore").read()
print(f"# {binp} ({cache})", file=sys.stderr)

rx = re.compile(r"function " + re.escape(o.pattern) + r"\(") if o.function else re.compile(re.escape(o.pattern))
for i, m in enumerate(rx.finditer(s)):
    if i >= o.n:
        break
    a = o.a if not o.function else max(o.a, 500)
    print(s[max(0, m.start() - (0 if o.function else o.b)) : m.end() + a].replace("\n", " "))
    print("---")
