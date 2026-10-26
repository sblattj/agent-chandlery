#!/usr/bin/env python3
"""ARIA snapshot each route of a web app through the cdp-toolkit CLI (`cdp`) in a tab of our own (new_page, then
close_page). Read-only. Per route: navigate, wait until the resource count is stable for 2.5 s (max 30 s), take_snapshot
with [uid] prefixes stripped and the localhost port normalized, final path, request paths (any origin) matching --api.
Diff two runs (A vs B) with --diff. Usage:
  snap.py BASE_URL OUT_DIR route [route ...] [--api REGEX]
  snap.py --diff A_DIR B_DIR
Exit 3 = CDP unreachable (browser debug port down)."""
import difflib, json, os, re, subprocess, sys, tempfile, time

NRM = [(re.compile(r'[0-9a-f]{8}-[0-9a-f-]{27}'), '<id>'), (re.compile(r'\d{4}-\d\d-\d\d[T ][\d:.]+Z?'), '<ts>'),
       (re.compile(r'\b\d+ (seconds?|minutes?|hours?|days?) ago\b'), '<ago>')]


def cdp(tool, **kw):
    cmd = ['cdp', tool] + [x for k, v in kw.items() for x in (f'--{k}', v if isinstance(v, str) else json.dumps(v))]
    # stdout to a file, not a pipe: the bun CLI cuts piped stdout at 64 KB on exit
    with tempfile.TemporaryFile('w+') as f:
        r = subprocess.run(cmd, stdout=f, stderr=subprocess.PIPE, text=True, timeout=60)
        f.seek(0); o = f.read()
    if r.returncode:
        raise RuntimeError(f'{tool}: {(r.stderr or o)[-300:]}')
    return o


def ev(label, expr):
    out = cdp('evaluate_script', target=f'label:{label}', json=json.dumps({'expression': expr}))
    try:
        d = json.loads(out)
        return d.get('value', d) if isinstance(d, dict) else d
    except ValueError:
        return out.strip()


def nrm(s):
    for p, r in NRM:
        s = p.sub(r, s)
    return s


def snap(base, out, routes, api):
    os.makedirs(out, exist_ok=True)
    label = f'route-snap-{os.getpid()}'
    try:
        cdp('new_page', url='about:blank', label=label)
    except Exception as e:
        print(f'CDP failed: {e}', file=sys.stderr); sys.exit(3)
    res = []
    try:
        for r in routes:
            err = ''
            try:
                cdp('navigate_page', target=f'label:{label}', url=base.rstrip('/') + r, timeoutMs=30000)
            except Exception as e:
                err = str(e)[:120]
            n, still, t0 = -1, 0, time.time()
            while time.time() - t0 < 30 and still < 5:
                time.sleep(0.5)
                m = ev(label, 'performance.getEntriesByType("resource").length')
                still = still + 1 if m == n else 0; n = m
            s = cdp('take_snapshot', target=f'label:{label}')
            try:
                s = json.loads(s).get('snapshot', s)
            except ValueError:
                pass
            aria = re.sub(r'https?://(localhost|127\.0\.0\.1):\d+', '<origin>', re.sub(r'\[\d+\] ?', '', s))
            final = ev(label, 'location.pathname')
            js = ('(() => [...new Set(performance.getEntriesByType("resource").map(e => new URL(e.name))'
                  '.filter(u => new RegExp(%s).test(u.pathname)).map(u => u.pathname))].sort())()') % json.dumps(api)
            paths = ev(label, js)
            paths = sorted({nrm(p) for p in (paths if isinstance(paths, list) else [])})
            res.append({'route': r, 'final': str(final), 'err': err, 'http': paths, 'aria': aria})
            print(f'{r} -> {final} {len(aria.splitlines())} lines, {len(paths)} paths {err}', flush=True)
    finally:
        try:
            cdp('close_page', target=f'label:{label}')
        except Exception as e:
            print(f'close_page: {e}', file=sys.stderr)
    json.dump(res, open(os.path.join(out, 'aria.json'), 'w'), indent=1)


def diff(a, b):
    A = {x['route']: x for x in json.load(open(os.path.join(a, 'aria.json')))}
    B = {x['route']: x for x in json.load(open(os.path.join(b, 'aria.json')))}
    bad = 0
    for r in sorted(set(A) | set(B)):
        x, y = A.get(r), B.get(r)
        if not (x and y):
            print(f'{r}: only in {"A" if x else "B"}'); bad += 1; continue
        d = list(difflib.unified_diff(nrm(x['aria']).splitlines(), nrm(y['aria']).splitlines(), 'A', 'B', lineterm='', n=1))
        same = not d and x['final'] == y['final'] and x['http'] == y['http'] and x['err'] == y['err']
        print(f'{r}: {"same" if same else "DIFF"}')
        if not same:
            bad += 1
            for k in ('final', 'err', 'http'):
                if x[k] != y[k]:
                    print(f'  {k}: A={x[k]} B={y[k]}')
            print('\n'.join('  ' + ln for ln in d[:80]))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    a = sys.argv[1:]
    if a[:1] == ['--diff']:
        diff(a[1], a[2])
    api = r'^/api/'
    if '--api' in a:
        i = a.index('--api'); api = a[i + 1]; del a[i:i + 2]
    if len(a) < 3:
        print(__doc__); sys.exit(2)
    snap(a[0], a[1], a[2:], api)
