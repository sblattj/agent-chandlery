#!/usr/bin/env bash
# Read-only: is the thing I'm about to relay already done? Usage:
#   check.sh tag v1.2.0-rc.3 | pr <id> | build <id>
# Azure DevOps (ADO) repos; needs the az CLI logged in.
# Env: R (repo dir, default: git toplevel of cwd), ADO_ORG, ADO_PROJECT, ADO_REPO
# (default: parsed from R's origin remote, Azure DevOps https or ssh form). If the user's agent instructions
# file (AGENTS.md / CLAUDE.md) names defaults, export them before calling. Otherwise ask the user.
# Azure DevOps public hosts (overridable for a proxy or mirror)
export AZ_HOST=${AZ_HOST:-dev.azure"."com} AZ_SSH=${AZ_SSH:-vs-ssh.visualstudio"."com}
R=${R:-$(git rev-parse --show-toplevel 2>/dev/null)}
url=$([ -n "$R" ] && git -C "$R" remote get-url origin 2>/dev/null)
case $url in
  *"$AZ_SSH"*|*ssh."$AZ_HOST"*) p=${url#*:v3/}; o=${p%%/*}; p=${p#*/}; pr=${p%%/*}; rp=${p#*/} ;;
  *"$AZ_HOST"*) p=${url#*"$AZ_HOST"/}; p=${p%%\?*}; o=${p%%/*}; p=${p#*/}; pr=${p%%/_git/*}; rp=${p##*/_git/} ;;
esac
ORG=${ADO_ORG:-$o}; PROJ=${ADO_PROJECT:-$(python3 -c 'import sys,urllib.parse;print(urllib.parse.unquote(sys.argv[1]))' "$pr")}; REPO=${ADO_REPO:-$rp}
kind=$1; shift
case $kind in tag|pr|build) [ -n "$ORG" ] && [ -n "$PROJ" ] && [ -n "$REPO" ] && [ -n "$R" ] || { echo "no ADO org/project/repo: run inside an ADO repo or set R / ADO_ORG / ADO_PROJECT / ADO_REPO"; exit 2; } ;; esac
TOK=$(az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv 2>/dev/null) || { echo "az token failed: run az login"; exit 1; }
ado() { perl -e 'alarm 60; exec @ARGV' python3 - "$TOK" "$ORG" "$PROJ" "$@" <<'PY'
import os,sys,json,urllib.request,urllib.parse
tok,org,proj,kind,*a=sys.argv[1:]
B=f"https://{os.environ['AZ_HOST']}/{org}/{urllib.parse.quote(proj)}/_apis"
def g(u): return json.loads(urllib.request.urlopen(urllib.request.Request(B+u,headers={"Authorization":"Bearer "+tok}),timeout=30).read().decode("utf-8-sig"))
if kind=="pr":
    repo,i=a; p=g(f"/git/repositories/{repo}/pullrequests/{i}?api-version=7.1")
    print(f"!{i} {p['status']}{' draft' if p.get('isDraft') else ''} merge={p.get('mergeStatus')} closed={p.get('closedDate','-')[:16]} by={(p.get('closedBy') or {}).get('displayName','-')} | {p['title'][:80]}")
    print("  merge commit:",(p.get('lastMergeCommit') or {}).get('commitId','-')[:8])
elif kind=="build":
    b=g(f"/build/builds/{a[0]}?api-version=7.1"); print(f"{b['id']} {b['status']} {b.get('result')} {b['sourceBranch']} {b['sourceVersion'][:8]}")
elif kind=="tagbuild":
    v=g(f"/build/builds?branchName=refs/tags/{a[0]}&queryOrder=queueTimeDescending&$top=1&api-version=7.1")["value"]
    print("  publish build:", f"{v[0]['id']} {v[0]['status']} {v[0].get('result')}" if v else "none")
PY
}
case $kind in
  tag) git -C "$R" fetch -q origin --tags 2>/dev/null; c=$(git -C "$R" rev-parse -q --verify "refs/tags/$1^{commit}"); if [ -n "$c" ]; then echo "tag $1: exists on ${c:0:8}"; else echo "tag $1: not found"; fi; [ -n "$c" ] && ado tagbuild "$1"; true ;;
  pr) ado pr "$REPO" "$1" ;;
  build) ado build "$1" ;;
  *) sed -n '2,7p' "$0"; exit 2 ;;
esac
