#!/usr/bin/env python3
"""Append each skill's pre-trim description into its body (under ## More triggers) so nothing is lost.

usage: keep-original.py --backup DIR [--skills-dir DIR] [--date YYYY-MM-DD] NAME [NAME...]
  --backup      a copy of the skills dir taken BEFORE trimming (DIR/<name>/SKILL.md)
  --skills-dir  the live skills dir (default: $CLAUDE_CONFIG_DIR/skills or ~/.claude/skills)
  --date        date stamped on the appended line (default: today)
The live SKILL.md must already have a '## More triggers' line; the original description is
inserted right after it. Skills that already carry an 'Original description' line are skipped.
"""
import argparse, datetime, os, re, sys

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument('names', nargs='+')
ap.add_argument('--backup', required=True)
ap.add_argument('--skills-dir', default=os.path.join(os.path.expanduser(os.environ.get('CLAUDE_CONFIG_DIR') or '~/.claude'), 'skills'))
ap.add_argument('--date', default=datetime.date.today().isoformat())
a = ap.parse_args()
for n in a.names:
    p = os.path.join(os.path.expanduser(a.skills_dir), n, 'SKILL.md'); s = open(p).read()
    if 'Original description (pre-trim' in s: print(n, 'already'); continue
    old = re.match(r'---\n(.*?)\n---', open(os.path.join(os.path.expanduser(a.backup), n, 'SKILL.md')).read(), re.S).group(1)
    d = re.search(r'^description:\s*(.*?)(?=^\w[\w-]*:|\Z)', old, re.S | re.M).group(1).strip().strip('"')
    m = re.search(r'## More triggers\n(?:\n)?[^\n]*\n', s)
    if not m: print(n, 'NO More triggers section'); continue
    s = s[:m.end()] + f'\nOriginal description (pre-trim, {a.date}): {d}\n' + s[m.end():]
    open(p, 'w').write(s); print(n, 'ok')
