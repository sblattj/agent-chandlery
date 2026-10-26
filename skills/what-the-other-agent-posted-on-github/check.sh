#!/bin/zsh
# What did the other agent do since <since>? New comments repo-wide (issues + PRs) and releases.
# usage: check.sh [owner/repo] [since ISO|"2h"] [issue#]
#   owner/repo defaults to the cwd checkout's GitHub repo; since defaults to 6h.
# env:   AS (gh account to read with, default: the repo owner)
# Read-only. "Nh" uses BSD date (macOS); on GNU date pass an ISO timestamp instead.
set -u
R=${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)}; SINCE=${2:-6h}; ISSUE=${3:-}
[[ -n $R ]] || { echo "usage: check.sh owner/repo [since] [issue#]  (or run inside a GitHub checkout)"; exit 2; }
AS=${AS:-${R%%/*}}; GH_TOKEN=$(gh auth token --user $AS 2>/dev/null) || { echo "gh has no account $AS"; exit 1; }; export GH_TOKEN
if [[ $SINCE =~ ^[0-9]+h$ ]]; then SINCE=$(date -u -v-${SINCE%h}H +%Y-%m-%dT%H:%M:%SZ); fi
echo "== $R since $SINCE (as $AS)"
echo "\n== releases"
gh api "repos/$R/releases?per_page=5" --jq ".[] | select(.published_at > \"$SINCE\") | \"\(.tag_name)  \(.published_at)\n\(.body)\n\""
echo "== comments (newest last; bot reviews collapsed)"
gh api --paginate "repos/$R/issues/comments?since=$SINCE&per_page=100" --jq '.[] |
  (.issue_url|split("/")|last) as $n |
  if (.body|test("<!-- prxref-summary -->")) then "#\($n) \(.created_at) \(.user.login): [prxref summary: \(.body|capture("## (?<t>[^\n]+)").t)]\n"
  else "#\($n) \(.created_at) \(.user.login):\n\(.body)\n---" end' |
  { [[ -n $ISSUE ]] && awk -v n="#$ISSUE " 'index($0,n)==1{p=1} /^#[0-9]+ /&&index($0,n)!=1{p=0} p' || cat; }
echo "\n== open issues touched"
gh issue list --repo $R --state all --search "updated:>=${SINCE%%T*}" --json number,title,state --jq '.[] | "#\(.number) [\(.state)] \(.title)"' | head -15
