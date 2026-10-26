#!/usr/bin/env bash
# work-overview: git-log-based high-level work overview for ONE person across
# specific local repos over a date range. Read-only. Run with `bash` (zsh-safe).
#
# Usage:
#   overview.sh [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--author REGEX] [--ticket-re ERE] [REPO ...]
#
# Defaults:
#   --since      14 days ago
#   --until      none (= now)
#   --author     `git config user.name`  (a NAME substring catches every email + name variant)
#   --ticket-re  '([A-Z]{2,}#|#)[0-9]{3,7}|[A-Z][A-Z0-9]+-[0-9]+'
#   REPO...      REPOS env (space-separated paths), else the current git repo
#
# Env overrides: SINCE, UNTIL, AUTHOR, TICKET_RE, REPOS.
set -euo pipefail

SINCE="${SINCE:-}"
UNTIL="${UNTIL:-}"
AUTHOR="${AUTHOR:-}"
TICKET_RE="${TICKET_RE:-([A-Z]{2,}#|#)[0-9]{3,7}|[A-Z][A-Z0-9]+-[0-9]+}"
REPOS_DEFAULT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
POS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --since)     SINCE="$2"; shift 2 ;;
    --until)     UNTIL="$2"; shift 2 ;;
    --author)    AUTHOR="$2"; shift 2 ;;
    --ticket-re) TICKET_RE="$2"; shift 2 ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) POS+=("$1"); shift ;;
  esac
done

if [ -z "$SINCE" ]; then
  SINCE=$(date -v-14d +%F 2>/dev/null || date -d '14 days ago' +%F)
  echo "(no --since given: using $SINCE, 14 days ago)"
fi
[ -n "$AUTHOR" ] || AUTHOR="$(git config user.name 2>/dev/null || true)"
[ -n "$AUTHOR" ] || { echo "error: no author: pass --author, set AUTHOR, or set git user.name" >&2; exit 2; }
if [ "${#POS[@]}" -gt 0 ]; then REPOS="${POS[*]}"; else REPOS="${REPOS:-$REPOS_DEFAULT}"; fi
[ -n "$REPOS" ] || { echo "error: no repos: pass REPO paths, set REPOS, or run inside a git repo" >&2; exit 2; }

UNTIL_ARG=(); [ -n "$UNTIL" ] && UNTIL_ARG=(--until "$UNTIL")

for repo in $REPOS; do
  if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then echo "### SKIP $repo (not a git repo)"; echo; continue; fi
  cd "$repo"
  branch=$(git rev-parse --abbrev-ref HEAD)
  name=$(basename "$repo")
  echo "==================================================================="
  echo "# $name   branch: $branch   author=~/$AUTHOR/   since=$SINCE ${UNTIL:+until=$UNTIL}"
  echo "==================================================================="

  echo "--- identities matched ---"
  git log --since="$SINCE" ${UNTIL_ARG[@]+"${UNTIL_ARG[@]}"} --author="$AUTHOR" \
    --format='%an <%ae>' | sort | uniq -c | sort -rn

  echo "--- commits per day ---"
  git log --since="$SINCE" ${UNTIL_ARG[@]+"${UNTIL_ARG[@]}"} --author="$AUTHOR" \
    --date=short --format='%ad' | sort | uniq -c

  echo "--- churn (no-merge) ---"
  git log --since="$SINCE" ${UNTIL_ARG[@]+"${UNTIL_ARG[@]}"} --author="$AUTHOR" \
    --no-merges --shortstat --format='' \
    | awk '/files? changed/{f+=$1; i+=$4; d+=$6}
           END{printf "files touched: %d  insertions: +%d  deletions: -%d\n", f, i, d}'

  echo "--- tickets referenced (top 30) ---"
  git log --since="$SINCE" ${UNTIL_ARG[@]+"${UNTIL_ARG[@]}"} --author="$AUTHOR" --format='%s' \
    | grep -oE "$TICKET_RE" | sort | uniq -c | sort -rn | head -30 \
    || echo "(none)"

  echo "--- commit subjects by day ---"
  git log --since="$SINCE" ${UNTIL_ARG[@]+"${UNTIL_ARG[@]}"} --author="$AUTHOR" \
    --date=short --format='%ad|%s' | sort -u

  echo
done
