#!/usr/bin/env python3
"""swarm.py: save workflow runs and measure drift between them.

  swarm.py save <runId|task.output|journal.jsonl> [--slug S]   -> $SWARM_STATE/<slug>/<runId>.json
  (SWARM_STATE defaults to ~/.local/state/swarm; transcripts come from $CLAUDE_CONFIG_DIR/projects, default ~/.claude/projects)
  swarm.py drift <run.json|runId|path> <run.json|...> [...] [--threshold 0.75] [--json]
  swarm.py ls [slug]

Swarm runs (swarm.workflow.js) save their verified claims directly. Any other workflow
falls back to the journal: dicts with claim/title become claims (verdict from verdict/status),
and verdict-only results are keyed by their agent label.
"""
import difflib, glob, json, os, re, sys

STATE = os.path.expanduser(os.environ.get('SWARM_STATE') or '~/.local/state/swarm')
PROJ = os.path.join(os.path.expanduser(os.environ.get('CLAUDE_CONFIG_DIR') or '~/.claude'), 'projects')


def find_paths(ref):
    """Return (runId, output_path|None, journal_path|None)."""
    if os.path.isfile(ref):
        if ref.endswith('journal.jsonl'):
            return os.path.basename(os.path.dirname(ref)), None, ref
        return os.path.splitext(os.path.basename(ref))[0], ref, None
    j = glob.glob(f'{PROJ}/*/*/subagents/workflows/{ref}/journal.jsonl')
    return ref, None, (j[0] if j else None)


def norm(s):
    return re.sub(r'[^a-z0-9:./-]+', ' ', (s or '').lower()).strip()


def from_output(path):
    d = json.load(open(path))
    r = d.get('result', d)
    if isinstance(r, dict) and isinstance(r.get('claims'), list):
        cl = [{'key': c.get('key') or c.get('id'), 'claim': c.get('claim', ''), 'verdict': c.get('verdict'),
               'verdict2': c.get('verdict2'), 'unit': c.get('unit')} for c in r['claims']]
        return {'kind': 'swarm', 'goal': r.get('goal'), 'stats': r.get('stats'), 'tokens': d.get('totalTokens'),
                'agents': d.get('agentCount'), 'claims': cl}
    return None


def walk(o, out, label):
    if isinstance(o, dict):
        text = o.get('claim') or o.get('title')
        if isinstance(text, str):
            out.append({'key': o.get('key'), 'claim': text,
                        'verdict': o.get('verdict') or o.get('status'), 'unit': label})
            return
        if 'verdict' in o:
            out.append({'key': label, 'claim': str(o.get('evidence') or o.get('reason') or '')[:300],
                        'verdict': o['verdict'], 'unit': label})
            return
        for v in o.values():
            walk(v, out, label)
    elif isinstance(o, list):
        for v in o:
            walk(v, out, label)


def from_journal(path):
    lab, cl = {}, []
    for line in open(path):
        d = json.loads(line)
        if d.get('type') == 'started':
            lab[d['key']] = d.get('label') or d['key'][:12]
        elif d.get('type') == 'result':
            walk(d.get('result'), cl, lab.get(d['key'], d['key'][:12]))
    return {'kind': 'journal', 'claims': cl, 'agents': len(lab)}


def load(ref):
    if ref.endswith('.json') and os.path.isfile(ref) and ref.startswith(STATE):
        return json.load(open(ref))
    hits = glob.glob(f'{STATE}/*/{ref}.json')
    if hits:
        return json.load(open(hits[0]))
    run, out, jr = find_paths(ref)
    data = (from_output(out) if out else None) or (from_journal(jr) if jr else None)
    if data is None and out:
        # task output without swarm claims: try its journal by runId inside the file
        jr = find_paths(json.load(open(out)).get('runId', run))[2]
        data = from_journal(jr) if jr else None
    if data is None:
        sys.exit(f'cannot load {ref}: no swarm output or journal found')
    data['run'] = run
    return data


def cmd_save(argv):
    ref = argv[0]
    slug = argv[argv.index('--slug') + 1] if '--slug' in argv else 'default'
    data = load(ref)
    os.makedirs(f'{STATE}/{slug}', exist_ok=True)
    p = f"{STATE}/{slug}/{data['run']}.json"
    json.dump(data, open(p, 'w'), indent=1)
    print(f"saved {len(data['claims'])} claims ({data['kind']}) -> {p}")


def match(a, b, thr):
    """Greedy match: exact key, then exact normalized text, then fuzzy text >= thr."""
    pairs, ub = [], set(range(len(b)))
    for i, ca in enumerate(a):
        best, bs = None, 0.0
        for j in ub:
            cb = b[j]
            if ca.get('key') and ca.get('key') == cb.get('key'):
                best, bs = j, 2.0; break
            s = 1.5 if norm(ca['claim']) == norm(cb['claim']) else difflib.SequenceMatcher(None, norm(ca['claim']), norm(cb['claim'])).ratio()
            if s > bs:
                best, bs = j, s
        if best is not None and bs >= thr:
            pairs.append((i, best)); ub.discard(best)
    return pairs


def pair_report(A, B, thr):
    a, b = A['claims'], B['claims']
    pairs = match(a, b, thr)
    union = len(a) + len(b) - len(pairs)
    jac = len(pairs) / union if union else 1.0
    flips = [(a[i], b[j]) for i, j in pairs if (a[i].get('verdict') or '') != (b[j].get('verdict') or '')]
    agree = 1 - len(flips) / len(pairs) if pairs else 1.0
    ma, mb = {i for i, _ in pairs}, {j for _, j in pairs}
    return {'a': A['run'], 'b': B['run'], 'claims_a': len(a), 'claims_b': len(b), 'matched': len(pairs),
            'jaccard': round(jac, 3), 'verdict_agreement': round(agree, 3), 'reliability': round(jac * agree, 3),
            'flips': [{'claim': x['claim'][:140], 'a': x.get('verdict'), 'b': y.get('verdict')} for x, y in flips],
            'only_a': [a[i]['claim'][:140] for i in range(len(a)) if i not in ma],
            'only_b': [b[j]['claim'][:140] for j in range(len(b)) if j not in mb]}


def cmd_drift(argv):
    thr = float(argv[argv.index('--threshold') + 1]) if '--threshold' in argv else 0.75
    refs = [x for i, x in enumerate(argv) if not x.startswith('--') and (i == 0 or argv[i - 1] != '--threshold')]
    if len(refs) < 2:
        sys.exit('drift needs 2+ runs')
    runs = [load(r) for r in refs]
    reps = [pair_report(runs[i], runs[j], thr) for i in range(len(runs)) for j in range(i + 1, len(runs))]
    mean = round(sum(r['reliability'] for r in reps) / len(reps), 3)
    if '--json' in argv:
        print(json.dumps({'mean_reliability': mean, 'pairs': reps}, indent=1)); return
    for r in reps:
        print(f"{r['a']} vs {r['b']}: claims {r['claims_a']}/{r['claims_b']}, matched {r['matched']}, "
              f"overlap {r['jaccard']:.0%}, verdict agreement {r['verdict_agreement']:.0%}, reliability {r['reliability']:.0%}")
        for f in r['flips'][:10]:
            print(f"  flip  {f['a']} -> {f['b']}: {f['claim']}")
        for c in r['only_a'][:5]:
            print(f"  only A: {c}")
        for c in r['only_b'][:5]:
            print(f"  only B: {c}")
        more = len(r['flips']) - 10, len(r['only_a']) - 5, len(r['only_b']) - 5
        if max(more) > 0:
            print(f"  (+{max(0,more[0])} flips, +{max(0,more[1])} only A, +{max(0,more[2])} only B not shown; --json for all)")
    print(f"mean reliability {mean:.0%} over {len(reps)} pair(s), match threshold {thr}")


def cmd_ls(argv):
    for p in sorted(glob.glob(f"{STATE}/{argv[0] if argv else '*'}/*.json")):
        d = json.load(open(p))
        print(f"{os.path.relpath(p, STATE)}  {d['kind']}  claims={len(d['claims'])}  stats={d.get('stats')}")


if __name__ == '__main__':
    if len(sys.argv) < 2 or sys.argv[1] not in ('save', 'drift', 'ls'):
        sys.exit(__doc__)
    {'save': cmd_save, 'drift': cmd_drift, 'ls': cmd_ls}[sys.argv[1]](sys.argv[2:])
