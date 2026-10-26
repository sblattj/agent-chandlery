#!/usr/bin/env python3
"""Leak-lint issue text before filing it on a public/personal GitHub repo.

Reports PII / employer / secret hits by line and exits 1 if any are found, so
the caller keeps rewriting until the draft is clean.

Usage:
  leak_lint.py [--denylist PATH] [--blocklist PATH] FILE [FILE ...]

Patterns come from three places:
  - built-in structural detectors (emails, tokens, home paths, ...)
  - reference/denylist.txt next to this script (generic, shareable)
  - the local-only blocklist ~/.config/scrub/blocklist.txt (or $SCRUB_BLOCKLIST)
    holding employer/teammate/internal terms. It is never committed. If it is
    missing the linter warns and runs without it.
"""
from __future__ import annotations
import argparse
import os
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
DEFAULT_DENYLIST = HERE.parent / "reference" / "denylist.txt"
DEFAULT_BLOCKLIST = pathlib.Path(
    os.environ.get("SCRUB_BLOCKLIST", "~/.config/scrub/blocklist.txt")).expanduser()

# Always-on structural detectors. (label, compiled regex)
BUILTIN = [
    ("email", re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")),
    ("github-token", re.compile(r"gh[opsu]_[A-Za-z0-9]{20,}")),
    ("aws-access-key", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("private-key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("secret-assignment", re.compile(
        r"(?i)\b(secret|password|passwd|api[_-]?key|access[_-]?token|bearer)\b\s*[:=]\s*\S+")),
    # Spelled so this file does not match its own detectors when linted.
    ("home-path", re.compile(r"/(?:Users|home)/[^/\s]+")),
    ("worktree-or-temp-path", re.compile(
        r"(?:~|/(?:Users)/[^/\s]+)/\.wt/\S+|/private/(?:tmp)/\S+|\bscratch[p]ad\b")),
    ("azure-devops", re.compile(r"(?i)\b(?:dev\.azure\.com|[\w.-]*\.visualstudio\.com)\b")),
]


def load_denylist(path: pathlib.Path):
    pats = []
    if not path.exists():
        return pats
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("re:"):
            try:
                pats.append(("denylist", re.compile(line[3:].strip(), re.I)))
            except re.error as e:
                print(f"warning: bad regex in denylist: {line!r}: {e}", file=sys.stderr)
            continue
        esc = re.escape(line)
        lb = r"\b" if (line[:1].isalnum() or line[:1] == "_") else ""
        rb = r"\b" if (line[-1:].isalnum() or line[-1:] == "_") else ""
        pats.append(("denylist", re.compile(lb + esc + rb, re.I)))
    return pats


def scan(text: str, patterns):
    seen = set()
    hits = []
    for lineno, line in enumerate(text.splitlines(), 1):
        for label, rx in patterns:
            for m in rx.finditer(line):
                frag = m.group(0)
                key = (lineno, label, frag)
                if key in seen:
                    continue
                seen.add(key)
                hits.append((lineno, label, frag))
    return hits


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("files", nargs="+")
    ap.add_argument("--denylist", default=str(DEFAULT_DENYLIST))
    ap.add_argument("--blocklist", default=str(DEFAULT_BLOCKLIST))
    args = ap.parse_args()

    blocklist = pathlib.Path(args.blocklist).expanduser()
    if not blocklist.exists():
        print(f"warning: local blocklist not found at {blocklist}; employer/teammate "
              "terms are NOT being checked. Create it (one term or re:regex per line) "
              "or set SCRUB_BLOCKLIST.", file=sys.stderr)
    patterns = (BUILTIN + load_denylist(pathlib.Path(args.denylist))
                + load_denylist(blocklist))
    total = 0
    for f in args.files:
        p = pathlib.Path(f)
        if not p.exists():
            print(f"error: no such file: {f}", file=sys.stderr)
            return 2
        hits = scan(p.read_text(encoding="utf-8"), patterns)
        for lineno, label, frag in hits:
            print(f'{f}:{lineno} [{label}] "{frag}"')
        total += len(hits)

    if total:
        print(f"\nFAIL: {total} potential leak(s). Reword and re-run.", file=sys.stderr)
        return 1
    print("clean: no leaks detected")
    return 0


if __name__ == "__main__":
    sys.exit(main())
