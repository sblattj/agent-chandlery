#!/usr/bin/env bash
# dump.sh: write machine-readable "what shipped" evidence files for commitment reconciliation.
# Outputs (in --out DIR):
#   <gh-repo-name>-prs.json      the author's GitHub PRs (gh --author @me), all states (gh pr list --json), one per GitHub repo
#   <ado-repo>-ado-prs.json      ADO PRs, all states (az repos pr list; needs --organization/--project or it prints nothing)
#   <repo>-commits.txt           the author's commits on ALL branches since DATE: "date hash refs subject"
#   transcripts.txt              only with --ws: dated transcript/notes folders (name, date) so units can pick "folders dated after the meeting"
#   MANIFEST.txt                 counts + the exact commands used
# Usage: dump.sh [--since YYYY-MM-DD] [--out DIR] [--author PATTERN] [--gh-repo OWNER/NAME]... [--ado-repo NAME]... [--ws DIR] [repo_path ...]
# Repos: args, else $EVIDENCE_REPOS (space-separated paths), else the git repo containing cwd; none -> exit 2.
# PR sources are inferred from each repo's origin remote: github.com -> gh, Azure DevOps (<host>/<org>/<project>/_git/<repo>) -> az.
# --gh-repo / --ado-repo add PR sources with no local checkout; --ado-repo needs env ADO_ORG (your Azure DevOps org URL)
# and ADO_PROJECT. Defaults: since $EVIDENCE_SINCE or 30 days ago, out ./evidence, author $EVIDENCE_AUTHOR or
# `git config --global user.name`, ws $EVIDENCE_WS (unset = no transcripts.txt). Read-only.
set -uo pipefail
SINCE="${EVIDENCE_SINCE:-$(date -v-30d +%F 2>/dev/null || date -d '30 days ago' +%F)}"; OUT="./evidence"; AUTHOR="${EVIDENCE_AUTHOR:-$(git config --global user.name 2>/dev/null)}"
GH_REPOS=(); ADO_REPOS=(); WS="${EVIDENCE_WS:-}"; REPOS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since) SINCE="$2"; shift 2 ;; --out) OUT="$2"; shift 2 ;; --author) AUTHOR="$2"; shift 2 ;;
    --gh-repo) GH_REPOS+=("$2"); shift 2 ;; --ado-repo) ADO_REPOS+=("$2"); shift 2 ;; --ws) WS="$2"; shift 2 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) REPOS+=("$1"); shift ;;
  esac
done
[[ ${#REPOS[@]} -eq 0 && -n "${EVIDENCE_REPOS:-}" ]] && read -ra REPOS <<<"$EVIDENCE_REPOS"
if [[ ${#REPOS[@]} -eq 0 ]]; then top="$(git rev-parse --show-toplevel 2>/dev/null)"; [[ -n "$top" ]] && REPOS=("$top"); fi
if [[ ${#REPOS[@]} -eq 0 && ${#GH_REPOS[@]} -eq 0 && ${#ADO_REPOS[@]} -eq 0 ]]; then
  echo "dump.sh: no repos. Pass repo paths, set EVIDENCE_REPOS, or run inside a repo." >&2; exit 2; fi
[[ -z "$AUTHOR" ]] && { echo "dump.sh: no author. Pass --author or set EVIDENCE_AUTHOR." >&2; exit 2; }
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"; M="$OUT/MANIFEST.txt"; : > "$M"
log(){ echo "$*" | tee -a "$M"; }
count(){ python3 -I -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$1" 2>/dev/null || echo '?'; }
log "evidence dump $(date '+%F %H:%M') since=$SINCE author=$AUTHOR out=$OUT"
ADO_TRIPLES=()   # "org|project|repo"
for r in ${ADO_REPOS[@]+"${ADO_REPOS[@]}"}; do
  if [[ -n "${ADO_ORG:-}" && -n "${ADO_PROJECT:-}" ]]; then ADO_TRIPLES+=("${ADO_ORG%/}|$ADO_PROJECT|$r")
  else log "$r-ado-prs.json: SKIPPED (--ado-repo needs ADO_ORG and ADO_PROJECT)"; fi
done
# commits, all branches; collect PR sources from remotes
for repo in ${REPOS[@]+"${REPOS[@]}"}; do
  n="$(basename "$repo")"
  if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then log "$n-commits.txt: NOT A GIT REPO ($repo)"; continue; fi
  git -C "$repo" log --all --author="$AUTHOR" --since="$SINCE 00:00" --date=short --format='%ad %h %D %s' > "$OUT/$n-commits.txt" 2>/dev/null
  log "$n-commits.txt: $(wc -l < "$OUT/$n-commits.txt" | tr -d ' ') commits  (git -C $repo log --all --author=$AUTHOR --since='$SINCE 00:00')"
  url="$(git -C "$repo" remote get-url origin 2>/dev/null)"
  if [[ "$url" =~ github\.com[:/]([^/]+)/([^/]+)$ ]]; then GH_REPOS+=("${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}")
  elif [[ "$url" =~ (dev[.]azure[.]com)/([^/]+)/([^/]+)/_git/([^/?]+) ]]; then   # https remote, host captured
    ADO_TRIPLES+=("https://${BASH_REMATCH[1]}/${BASH_REMATCH[2]}|${BASH_REMATCH[3]//%20/ }|${BASH_REMATCH[4]}")
  elif [[ "$url" =~ ssh[.](dev[.]azure[.]com):v3/([^/]+)/([^/]+)/([^/]+)$ ]]; then  # ssh remote: org URL drops the ssh. prefix
    ADO_TRIPLES+=("https://${BASH_REMATCH[1]}/${BASH_REMATCH[2]}|${BASH_REMATCH[3]//%20/ }|${BASH_REMATCH[4]}")
  fi
done
# GitHub PRs
for GH_REPO in ${GH_REPOS[@]+"${GH_REPOS[@]}"}; do
  GHN="${GH_REPO##*/}"
  if gh pr list -R "$GH_REPO" --author @me --state all --limit 200 \
      --json number,title,state,mergedAt,createdAt,updatedAt,isDraft,url,reviewDecision,baseRefName > "$OUT/$GHN-prs.json" 2>/dev/null; then
    log "$GHN-prs.json: $(count "$OUT/$GHN-prs.json") PRs  (gh pr list -R $GH_REPO --author @me --state all)"
  else log "$GHN-prs.json: FAILED (gh auth? gh api user --jq .login)"; echo '[]' > "$OUT/$GHN-prs.json"; fi
done
# ADO PRs: both --organization and --project are required, otherwise az returns nothing even inside the repo
for t in ${ADO_TRIPLES[@]+"${ADO_TRIPLES[@]}"}; do
  IFS='|' read -r org proj ADO_REPO <<<"$t"
  if az repos pr list --organization "$org" --project "$proj" \
      --repository "$ADO_REPO" --status all --top 200 -o json > "$OUT/$ADO_REPO-ado-prs.json" 2>/dev/null; then
    log "$ADO_REPO-ado-prs.json: $(count "$OUT/$ADO_REPO-ado-prs.json") PRs  (az repos pr list --organization $org --project '$proj' --repository $ADO_REPO --status all)"
  else log "$ADO_REPO-ado-prs.json: FAILED (az login / az devops login?)"; echo '[]' > "$OUT/$ADO_REPO-ado-prs.json"; fi
done
# transcript folders
if [[ -n "$WS" && -d "$WS" ]]; then
  ls "$WS" | grep -E '^20[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{4}' | awk '{print $1" "substr($1,1,10)}' > "$OUT/transcripts.txt"
  log "transcripts.txt: $(wc -l < "$OUT/transcripts.txt" | tr -d ' ') folders under $WS (name date)"
fi
echo "--- $M"; cat "$M"
