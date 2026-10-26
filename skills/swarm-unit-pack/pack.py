#!/usr/bin/env python3
"""pack.py: turn a list of items into per-unit files + one shared rules file + Workflow args that fit the args cap.
usage:
  pack.py items.json --base DIR --rules RULES.md [--tier haiku|sonnet|opus] [--goal TEXT] [--compare] [--mcp] [--prefix r]
  pack.py check ARGS.json                      # size report for an existing Workflow args file
items.json: a JSON list; each item is a dict (any shape). Its unit id = item['id'] if present, else <prefix><NN>.
Writes: DIR/<id>.json (the item), copies RULES.md to DIR/_RULES.md (if not already inside DIR),
        DIR/_units.json (units with one-line prompts), DIR/_args.json (full Workflow args).
Then: Workflow({scriptPath: <abs path to the swarm skill>/swarm.workflow.js, args: <contents of DIR/_args.json>}).
Why: 60 inline prompts came to 97KB and the Workflow call would not take them; one-line prompts
pointing at files kept the same run at about 8 to 11KB.
"""
import json, os, shutil, sys
WARN = 30_000  # bytes; 97KB failed, about 8KB worked. Treat anything above this as "split it".
def size_report(args):
    s = json.dumps(args); units = args.get('units') or args.get('claims') or []
    big = sorted(((len(json.dumps(u)), u.get('id')) for u in units), reverse=True)[:3]
    print(f"args: {len(s):,} bytes, {len(units)} units, goal {len(args.get('goal',''))} chars; largest units: {big}")
    if len(s) > WARN: print(f"WARNING: over {WARN:,} bytes. Move per-unit text into files and keep prompts to one line.")
    return len(s)
def main(a):
    if a and a[0] == 'check':
        size_report(json.load(open(a[1]))); return
    opt = lambda k, d=None: a[a.index(k)+1] if k in a else d
    items = json.load(open(a[0])); base = os.path.abspath(opt('--base', '.')); rules = opt('--rules')
    tier = opt('--tier', 'sonnet'); prefix = opt('--prefix', 'u'); goal = opt('--goal', '')
    os.makedirs(base, exist_ok=True)
    rpath = None
    if rules:
        rules = os.path.abspath(rules); rpath = os.path.join(base, '_RULES.md')
        if rules != rpath: shutil.copy(rules, rpath)
    units = []
    for i, it in enumerate(items, 1):
        uid = str(it.get('id') if isinstance(it, dict) and it.get('id') else f"{prefix}{i:02d}")
        p = os.path.join(base, f"{uid}.json"); json.dump(it, open(p, 'w'), indent=1)
        one = (it.get('summary') or it.get('action') or it.get('title') or '') if isinstance(it, dict) else ''
        prompt = f"Unit file: {p}." + (f" {one[:160]}." if one else '') + (f" Follow {rpath} exactly." if rpath else '')
        u = {'id': uid, 'tier': tier, 'prompt': prompt}
        if '--mcp' in a: u['needs_mcp'] = True
        units.append(u)
    if rpath and rpath not in goal: goal = (goal + ' ' if goal else '') + f"Shared rules: {rpath}. Unit files: {base}/<id>.json. All paths absolute."
    args = {'goal': goal, 'mode': 'read', 'compare': '--compare' in a, 'synth': False, 'units': units}
    json.dump(units, open(os.path.join(base, '_units.json'), 'w'), indent=0)
    json.dump(args, open(os.path.join(base, '_args.json'), 'w'), indent=0)
    print(f"wrote {len(units)} unit files + _units.json + _args.json in {base}")
    size_report(args)
if __name__ == '__main__': main(sys.argv[1:])
