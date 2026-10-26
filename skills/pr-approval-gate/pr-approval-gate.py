#!/usr/bin/env python3
"""pr-approval-gate: what still blocks each of your open PRs from merging.

Per PR: draft/ready, merge state (BEHIND, DIRTY...), current approvals, and every
CODEOWNERS rule its files hit that no approver satisfies (last matching rule wins).
Read-only.

Usage: pr-approval-gate.py [-R owner/repo | repo-folder] [--author LOGIN] [--pr N ...] [--json]
  default repo: the cwd's origin. repo-folder: a folder under $PR_GATE_ROOT (default ~/dev).
"""
import argparse, base64, json, os, re, subprocess, sys

def gh(args, cwd=None):
    r = subprocess.run(["gh", *args], capture_output=True, text=True, cwd=cwd)
    if r.returncode:
        raise RuntimeError(r.stderr.strip() or f"gh {' '.join(args)} failed")
    return r.stdout

def repo_slug(target):
    cwd = None
    if target and "/" not in target:
        cwd = os.path.join(os.path.expanduser(os.environ.get("PR_GATE_ROOT", "~/dev")), target)
        target = None
    if target:
        return target, cwd
    url = subprocess.run(["git", "remote", "get-url", "origin"], capture_output=True, text=True, cwd=cwd).stdout.strip()
    m = re.search(r"github\.com[:/](.+?)(?:\.git)?$", url)
    if not m:
        sys.exit(f"no GitHub origin in {cwd or os.getcwd()}; pass -R owner/repo")
    return m.group(1), cwd

def pattern_regex(p):
    # GitHub CODEOWNERS (gitignore-like): leading / anchors to root, trailing / = directory,
    # a pattern with no inner / matches at any depth, * stays within one segment, ** spans.
    anchored = p.startswith("/") or "/" in p.rstrip("/")
    p = p.lstrip("/")
    directory = p.endswith("/")
    p = p.rstrip("/")
    out, i = "", 0
    while i < len(p):
        if p.startswith("**", i):
            out += ".*"; i += 2
        elif p[i] == "*":
            out += "[^/]*"; i += 1
        elif p[i] == "?":
            out += "[^/]"; i += 1
        else:
            out += re.escape(p[i]); i += 1
    if p == "*" or p == "**":
        return re.compile(".*")
    head = "^" if anchored else "^(?:.*/)?"
    tail = "/.*$" if directory else "(?:/.*)?$"
    return re.compile(head + out + tail)

def load_codeowners(slug, ref, cache={}):
    if (slug, ref) in cache:
        return cache[(slug, ref)]
    rules = []
    for path in (".github/CODEOWNERS", "CODEOWNERS", "docs/CODEOWNERS"):
        try:
            raw = json.loads(gh(["api", f"repos/{slug}/contents/{path}?ref={ref}"]))
        except RuntimeError:
            continue
        for line in base64.b64decode(raw["content"]).decode().splitlines():
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            pat, *owners = line.split()
            rules.append((pat, pattern_regex(pat), [o.lstrip("@") for o in owners]))
        break
    cache[(slug, ref)] = rules
    return rules

def owner_rule(rules, path):
    hit = None
    for rule in rules:  # last match wins
        if rule[1].match(path):
            hit = rule
    return hit

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("target", nargs="?")
    ap.add_argument("-R", "--repo")
    ap.add_argument("--author", default="@me")
    ap.add_argument("--pr", type=int, nargs="*")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    slug, cwd = repo_slug(a.repo or a.target)
    fields = "number,title,url,isDraft,baseRefName,headRefName,reviewDecision,mergeStateStatus,latestReviews,reviewRequests,files"
    prs = json.loads(gh(["pr", "list", "-R", slug, "--author", a.author, "--state", "open", "--limit", "200", "--json", fields], cwd=cwd))
    heads = {p["headRefName"] for p in prs}
    head_pr = {p["headRefName"]: p["number"] for p in prs}
    if a.pr:
        prs = [p for p in prs if p["number"] in a.pr]
    default = json.loads(gh(["repo", "view", slug, "--json", "defaultBranchRef"], cwd=cwd))["defaultBranchRef"]["name"]
    out = []
    for p in prs:
        approvers = sorted({r["author"]["login"] for r in p["latestReviews"] if r["state"] == "APPROVED"})
        changes = sorted({r["author"]["login"] for r in p["latestReviews"] if r["state"] == "CHANGES_REQUESTED"})
        # stacked PRs only reach the trunk later: judge owners against the trunk's CODEOWNERS
        ref = default if p["baseRefName"] in heads else p["baseRefName"]
        rules = load_codeowners(slug, ref)
        gaps = {}
        for f in p["files"]:
            hit = owner_rule(rules, f["path"])
            if not hit or not hit[2]:
                continue
            if set(hit[2]) & set(approvers):
                continue
            g = gaps.setdefault(hit[0], {"owners": hit[2], "files": 0})
            g["files"] += 1
        out.append({
            "number": p["number"], "title": p["title"], "url": p["url"],
            "draft": p["isDraft"], "base": p["baseRefName"], "stacked": p["baseRefName"] in heads, "parent": head_pr.get(p["baseRefName"]),
            "mergeState": p["mergeStateStatus"], "reviewDecision": p["reviewDecision"],
            "approvers": approvers, "changesRequested": changes,
            "files": len(p["files"]), "filesTruncated": len(p["files"]) >= 100,
            "ownerGaps": [{"pattern": k, **v} for k, v in gaps.items()],
            "requested": [r.get("login") or r.get("name") for r in p["reviewRequests"]],
        })
    if a.json:
        print(json.dumps({"repo": slug, "prs": out}, indent=1)); return
    print(f"{slug}: {len(out)} open PRs by {a.author}\n")
    for r in sorted(out, key=lambda r: (r["draft"], r["stacked"], -r["number"])):
        state = "draft" if r["draft"] else "ready"
        if r["stacked"]:
            state += f", stacked on #{r['parent']}"
        appr = ", ".join(r["approvers"]) or "none"
        gaps = "; ".join(f"{g['pattern']} -> {' or '.join(g['owners'])}" for g in r["ownerGaps"]) or "none"
        blocked = []
        if r["draft"]: blocked.append("mark ready")
        if r["ownerGaps"]: blocked.append("code owner")
        if r["changesRequested"]: blocked.append("changes requested by " + ", ".join(r["changesRequested"]))
        if r["reviewDecision"] == "REVIEW_REQUIRED" and not r["ownerGaps"]: blocked.append("more approvals")
        if r["mergeState"] in ("DIRTY",): blocked.append("conflicts")
        if r["mergeState"] == "BEHIND": blocked.append("behind base (sync, approvals stay)")
        print(f"#{r['number']} [{state}] {r['mergeState']} {r['title'][:70]}")
        print(f"   approved: {appr}")
        print(f"   owner gaps: {gaps}" + ("  (file list capped at 100)" if r["filesTruncated"] else ""))
        print(f"   needs: {', '.join(blocked) or 'nothing, mergeable'}\n")

if __name__ == "__main__":
    try:
        main()
    except RuntimeError as e:
        sys.exit(str(e))
