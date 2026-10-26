#!/usr/bin/env python3
"""pr-logic-trail: logic-only PR walkthrough, ordered by request path.

  trail.py prep <pr> [--repo owner/name] [--out DIR]   fetch diff, split test vs logic, write hunks.md + stops.json skeleton
  trail.py render DIR [--out FILE]                       render DIR/stops.json into HTML (validates hunk coverage)
"""
import argparse, html, json, os, re, subprocess, sys

TEST_RE = re.compile(r'(/test/|/tests/|__tests__/|\.test\.|\.spec\.|Test\.java$|IT\.java$|Tests?\.kt$|_test\.(go|py)$|(^|/)test_[^/]+\.py$|^e2e-tests/)')
IMPACTS = ("prod", "feature", "plumb")
DEFAULT_LABELS = {"prod": "Changes live targets", "feature": "Feature path only", "plumb": "Plumbing"}
TPL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "tpl.html")


def sh(*a):
    return subprocess.run(a, check=True, capture_output=True, text=True).stdout


def split_files(diff):
    out = []
    for p in re.split(r'(?=^diff --git )', diff, flags=re.M):
        if not p.strip():
            continue
        path = p.split('\n')[0].split(' b/', 1)[1]
        hunks = re.split(r'(?=^@@ )', p, flags=re.M)[1:]
        out.append((path, hunks))
    return out


def hunk_counts(h):
    a = r = 0
    for l in h.split('\n')[1:]:
        if l.startswith('+'): a += 1
        elif l.startswith('-'): r += 1
    return a, r


def cmd_prep(ns):
    repo = ns.repo or sh("gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner").strip()
    meta = json.loads(sh("gh", "pr", "view", str(ns.pr), "--repo", repo, "--json", "number,title,state,baseRefName,headRefName,url,isDraft"))
    diff = sh("gh", "pr", "diff", str(ns.pr), "--repo", repo)
    out = ns.out or os.path.join(os.getcwd(), f"pr-{ns.pr}-trail")
    os.makedirs(out, exist_ok=True)
    files = split_files(diff)
    logic = [(p, h) for p, h in files if not TEST_RE.search(p)]
    tests = [(p, h) for p, h in files if TEST_RE.search(p)]
    open(os.path.join(out, "logic.diff"), "w").write("".join("diff --git a/%s b/%s\n" % (p, p) + "".join(h) for p, h in logic))
    tl = sum(sum(hunk_counts(x)) for _, hs in tests for x in hs)
    md = [f"# PR #{meta['number']} {meta['title']}", f"test files {len(tests)} ({tl} lines); logic files {len(logic)}", ""]
    for p, hs in logic:
        md.append(f"## {p}")
        for i, h in enumerate(hs):
            a, r = hunk_counts(h)
            md.append(f"- [{i}] +{a} -{r}  {h.split(chr(10))[0][:110]}")
        md.append("")
    md.append("## test files (excluded)")
    md += [f"- {p}" for p, _ in tests]
    open(os.path.join(out, "hunks.md"), "w").write("\n".join(md) + "\n")
    tick = re.search(r'#?(\d{5,})', meta["title"])
    skel = {
        "pr": {"number": meta["number"], "repo": repo, "title": re.sub(r'^\[[^\]]*\]\s*', '', meta["title"]),
               "ticket": f"{os.environ.get('TICKET_PREFIX', '')}#{tick.group(1)}" if tick else "", "base": meta["baseRefName"],
               "state": "draft" if meta["isDraft"] else meta["state"].lower(), "url": meta["url"]},
        "sub": "TODO one sentence: what the reader is walking and in what order.",
        "rail": "Request path",
        "labels": dict(DEFAULT_LABELS),
        "test_files": len(tests), "test_lines": tl,
        "stops": [{"id": "stop1", "name": "TODO", "lede": "TODO",
                   "items": [{"file": os.path.basename(p), "hunks": list(range(len(hs))), "impact": "feature",
                              "title": "TODO", "note": "TODO", "fold": False} for p, hs in logic]}],
        "live": None,
    }
    sp = os.path.join(out, "stops.json")
    if os.path.exists(sp) and not ns.force:
        print(f"kept existing {sp} (use --force to overwrite)")
    else:
        json.dump(skel, open(sp, "w"), indent=2)
    print(f"{out}\n  logic {len(logic)} files, tests {len(tests)} files / {tl} lines\n  next: edit stops.json using hunks.md, then: trail.py render {out}")


def render_hunk(h):
    lines = h.rstrip('\n').split('\n')
    m = re.match(r'@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@(.*)', lines[0])
    o, n = int(m.group(1)), int(m.group(2))
    rows = []; a = r = 0
    for l in lines[1:]:
        if l.startswith('\\'): continue
        t = l[:1]; body = html.escape(l[1:]) or '&nbsp;'
        if t == '+':
            rows.append(f'<tr class="ad"><td class="ln"></td><td class="ln">{n}</td><td class="sg">+</td><td class="cd">{body}</td></tr>'); n += 1; a += 1
        elif t == '-':
            rows.append(f'<tr class="rm"><td class="ln">{o}</td><td class="ln"></td><td class="sg">&minus;</td><td class="cd">{body}</td></tr>'); o += 1; r += 1
        else:
            rows.append(f'<tr><td class="ln">{o}</td><td class="ln">{n}</td><td class="sg"></td><td class="cd">{body}</td></tr>'); o += 1; n += 1
    head = (f'<div class="hh"><span>{html.escape(lines[0].split("@@")[1].strip())}</span>'
            f'<span class="ctx">{html.escape(m.group(3).strip())}</span>'
            f'<span class="cnt"><b class="p">+{a}</b> <b class="m">&minus;{r}</b></span></div>')
    return head + '<div class="scroll"><table class="diff">' + ''.join(rows) + '</table></div>', a, r


def cnt(a, r):
    return f'<span class="cnt"><b class="p">+{a}</b> <b class="m">&minus;{r}</b></span>'


def cmd_render(ns):
    d = ns.dir
    cfg = json.load(open(os.path.join(d, "stops.json")))
    files = {os.path.basename(p): (p, hs) for p, hs in split_files(open(os.path.join(d, "logic.diff")).read())}
    L = {**DEFAULT_LABELS, **(cfg.get("labels") or {})}
    E = html.escape
    seen = {}; errs = []
    tot = dict.fromkeys(IMPACTS, 0)
    per_file = {b: {"lines": 0, "hunks": 0, "imp": set()} for b in files}
    nav = []; secs = []
    for i, st in enumerate(cfg["stops"], 1):
        cards = []; slines = 0; hasprod = False
        for it in st["items"]:
            fn, imp = it["file"], it["impact"]
            if fn not in files: errs.append(f"unknown file {fn}"); continue
            if imp not in IMPACTS: errs.append(f"{fn}: impact must be one of {IMPACTS}"); continue
            path, hunks = files[fn]
            body = ''; a = r = 0
            for k in it["hunks"]:
                if k >= len(hunks): errs.append(f"{fn}[{k}] out of range"); continue
                seen.setdefault((fn, k), []).append(st["id"])
                hb, ha, hr = render_hunk(hunks[k]); body += hb; a += ha; r += hr
            tot[imp] += a + r; slines += a + r; hasprod |= imp == "prod"
            pf = per_file[fn]; pf["lines"] += a + r; pf["hunks"] += len(it["hunks"]); pf["imp"].add(imp)
            note = f'<p class="note">{E(it.get("note",""))}</p>' if it.get("note") else ''
            inner = (f'<header class="ch"><span class="chip {imp}">{E(L[imp])}</span><h3>{E(it["title"])}</h3>'
                     f'<code class="path" title="{E(path)}">{E(fn)}</code></header>{note}')
            if it.get("fold"):
                cards.append(f'<details class="card fold" data-imp="{imp}"><summary>{inner}{cnt(a, r)}</summary>{body}</details>')
            else:
                cards.append(f'<article class="card" data-imp="{imp}">{inner}<details class="dw" open><summary>Diff {cnt(a, r)}</summary>{body}</details></article>')
        nav.append(f'<li><a href="#{E(st["id"])}" class="{"hasprod" if hasprod else ""}"><span class="no">{i}</span><span>{E(st["name"])}</span><span class="nl">{slines}</span></a></li>')
        secs.append(f'<section id="{E(st["id"])}" class="stop"><div class="sh"><span class="no">{i}</span><div><h2>{E(st["name"])}</h2>'
                    f'<p class="lede">{E(st.get("lede",""))}</p></div></div>{"".join(cards)}</section>')
    for fn, (_, hs) in files.items():
        for k in range(len(hs)):
            if (fn, k) not in seen: errs.append(f"unassigned hunk {fn}[{k}]")
    errs += [f"hunk {fn}[{k}] used in {v}" for (fn, k), v in seen.items() if len(v) > 1]
    if errs:
        sys.exit("render refused:\n  " + "\n  ".join(errs))

    logic_lines = sum(tot.values())
    prod_files = [f for f, v in per_file.items() if "prod" in v["imp"]]
    prod_hunks = sum(1 for (fn, k), _ in seen.items() for st in cfg["stops"] for it in st["items"]
                     if it["file"] == fn and k in it["hunks"] and it["impact"] == "prod")
    pr = cfg["pr"]
    live = cfg.get("live")
    live_html = ''
    if live:
        rows = ''.join(f'<tr><td>{c}</td><td class="was">{b}</td><td class="now">{a}</td></tr>' for c, b, a in live["rows"])
        st_line = f'<p class="st"><b>S-T:</b> {E(live["st"])}</p>' if live.get("st") else ''
        live_html = (f'<section id="live" class="stop"><div class="live"><h2>{E(live["title"])}</h2><p class="note">{live.get("note","")}</p>'
                     f'<div class="tw"><table><thead><tr><th>Case</th><th>{E(live.get("before", pr["base"]))}</th><th>PR #{pr["number"]}</th></tr></thead>'
                     f'<tbody>{rows}</tbody></table></div>{st_line}</div></section>')
        nav.append(f'<li><a href="#live" class="hasprod"><span class="no">!</span><span>{E(live.get("nav", "Live impact"))}</span><span class="nl"></span></a></li>')
    order = [f for st in cfg["stops"] for it in st["items"] for f in [it["file"]]]
    order = list(dict.fromkeys(order))
    frows = ''.join(
        f'<tr><td><code class="path" title="{E(files[f][0])}">{E(f)}</code></td><td class="n">{per_file[f]["lines"]}</td><td class="n">{per_file[f]["hunks"]}</td>'
        f'<td>{"".join(f"<span class=\"chip {i}\">{E(L[i])}</span>" for i in IMPACTS if i in per_file[f]["imp"])}</td></tr>' for f in order)
    w = lambda k: f'<span style="width:calc({tot[k]}/{max(logic_lines,1)}*100%);background:var(--{ {"prod":"prod","feature":"test","plumb":"plumb"}[k] })"></span>'
    leg = lambda k, extra='': f'<span><i style="background:var(--{ {"prod":"prod","feature":"test","plumb":"plumb"}[k] })"></i>{E(L[k])} <b>{tot[k]}</b> lines{extra}</span>'
    ptxt = f', {prod_hunks} changes, {len(prod_files)} file{"s" if len(prod_files)!=1 else ""}'
    meta = (f'<span>{len(files)+cfg.get("test_files",0)} files: <b>{len(files)} production code</b> + {cfg.get("test_files",0)} test files ({cfg.get("test_lines",0)} lines, not shown)</span>'
            f'<span>Diff vs <b>{E(pr["base"])}</b></span><span>Status <b>{E(pr["state"])}</b></span>')
    if prod_files:
        meta += f'<span><b>{len(prod_files)}</b> of {len(files)} production files also {E(L["prod"].lower())} ({", ".join(E(f) for f in prod_files)})</span>'
    sub = cfg.get("sub", "")
    rep = {
        "{{TITLE}}": E(cfg.get("page_title") or f"#{pr['number']} Logic Trail"),
        "{{EYEBROW}}": E(" · ".join(x for x in [f"{pr['repo'].split('/')[-1]} PR #{pr['number']}", pr.get("ticket", ""), "production code only"] if x)),
        "{{H1}}": E(pr["title"]), "{{SUB}}": E(sub), "{{META}}": meta,
        "{{LOGIC_LINES}}": str(logic_lines), "{{LOGIC_FILES}}": str(len(files)),
        "{{BAR}}": ''.join(w(k) for k in IMPACTS),
        "{{LEGEND}}": leg("prod", ptxt) + leg("feature") + leg("plumb"),
        "{{FILES}}": frows, "{{L_prod}}": E(L["prod"]), "{{L_feature}}": E(L["feature"]), "{{L_prod_lc}}": E(L["prod"].lower()),
        "{{RAIL}}": E(cfg.get("rail", "Request path")), "{{NAV}}": ''.join(nav), "{{SECTIONS}}": ''.join(secs), "{{LIVE}}": live_html,
    }
    t = open(TPL).read()
    left = sorted(set(re.findall(r'\{\{[A-Za-z_]+\}\}', t)) - set(rep))
    if left: sys.exit(f"template placeholders with no value: {left}")
    for k, v in rep.items(): t = t.replace(k, v)
    out = ns.out or os.path.join(d, f"pr-{pr['number']}-logic-trail.html")
    open(out, "w").write(t)
    print(json.dumps({"out": out, "lines": tot, "logic_lines": logic_lines, "logic_files": len(files), "prod_files": prod_files, "prod_changes": prod_hunks}))


ap = argparse.ArgumentParser()
sub = ap.add_subparsers(dest="cmd", required=True)
p = sub.add_parser("prep"); p.add_argument("pr", type=int); p.add_argument("--repo"); p.add_argument("--out"); p.add_argument("--force", action="store_true")
r = sub.add_parser("render"); r.add_argument("dir"); r.add_argument("--out")
ns = ap.parse_args()
{"prep": cmd_prep, "render": cmd_render}[ns.cmd](ns)
