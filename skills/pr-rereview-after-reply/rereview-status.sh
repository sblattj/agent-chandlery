#!/usr/bin/env bash
# Read-only: what changed on a PR since MY last review, and are the fixes the author claims actually on the head.
#   rereview-status.sh <pr-url> [reviewer-login]     # default reviewer: the gh account gh resolves for this repo
# Env: BACK=2 measures from my 2nd-to-last review (default 1 = last). REPO_DIR=<local clone> adds a git range-diff (old reviewed head vs new head), BASE (default: the PR's base).
set -euo pipefail
url="${1:?usage: rereview-status.sh <pr-url> [reviewer-login]}"
[[ "$url" =~ ^https://github\.com/([^/]+/[^/]+)/pull/([0-9]+) ]] || { echo "not a PR url: $url" >&2; exit 2; }
repo="${BASH_REMATCH[1]}"; n="${BASH_REMATCH[2]}"
me="${2:-$(gh api user --jq .login)}"

pr="$(gh api "repos/$repo/pulls/$n")"
head="$(jq -r .head.sha <<<"$pr")"; base="${BASE:-$(jq -r .base.ref <<<"$pr")}"
last="$(gh api --paginate --slurp "repos/$repo/pulls/$n/reviews" | jq -c --arg me "$me" --arg b "${BACK:-1}" '[.[][]|select(.user.login==$me and .state!="PENDING")]|.[-($b|tonumber)] // empty')"
[ -n "$last" ] || { echo "no review by $me on $repo#$n"; exit 1; }
since="$(jq -r .submitted_at <<<"$last")"; old="$(jq -r .commit_id <<<"$last")"
echo "$repo#$n  my last review: $(jq -r .state <<<"$last") at $since on ${old:0:10}  head now: ${head:0:10}  base: $base"

cmp="$(gh api "repos/$repo/compare/$old...$head" --jq '"\(.status) ahead=\(.ahead_by) behind=\(.behind_by)"')"
echo "old->head: $cmp   (diverged = force-pushed/rebased; check range-diff before trusting new code exists)"

echo; echo "== activity by others since $since"
gh api --paginate --slurp "repos/$repo/issues/$n/comments" | jq -r --arg me "$me" --arg s "$since" \
  '.[][]|select(.user.login!=$me and .created_at>$s)|"-- comment \(.user.login) \(.created_at)\n\(.body)\n"'
gh api --paginate --slurp "repos/$repo/pulls/$n/comments" | jq -r --arg me "$me" --arg s "$since" \
  '.[][]|select(.user.login!=$me and .created_at>$s)|"-- inline \(.user.login) \(.path):\(.line // .original_line)\n\(.body)\n"'
gh api --paginate --slurp "repos/$repo/pulls/$n/reviews" | jq -r --arg me "$me" --arg s "$since" \
  '.[][]|select(.user.login!=$me and .submitted_at>$s and (.state!="COMMENTED" or (.body|length)>0))|"-- review \(.user.login) \(.state) \(.submitted_at)\n\(.body)\n"'
gh api --paginate --slurp "repos/$repo/issues/$n/timeline" | jq -r --arg s "$since" \
  '.[][]|select(.event=="head_ref_force_pushed" and .created_at>$s)|"-- FORCE-PUSH \(.actor.login) \(.created_at)"'

echo "== commits claimed in replies vs head"
claims="$( { gh api --paginate --slurp "repos/$repo/issues/$n/comments"; gh api --paginate --slurp "repos/$repo/pulls/$n/comments"; gh api --paginate --slurp "repos/$repo/pulls/$n/reviews"; } \
  | jq -r --arg me "$me" --arg s "$since" '.[][]|select(.user.login!=$me and ((.created_at // .submitted_at)>$s))|.body' \
  | grep -oE '\b[0-9a-f]{7,40}\b' | grep -E '[a-f]' | grep -E '[0-9]' | sort -u || true)"
if [ -z "$claims" ]; then echo "(none named)"; fi
for c in $claims; do
  st="$(gh api "repos/$repo/compare/$c...$head" --jq .status 2>/dev/null || echo unknown-sha)"
  case "$st" in identical|ahead) v="ON HEAD" ;; diverged|behind) v="NOT ON HEAD" ;; *) v="$st" ;; esac
  msg="$(gh api "repos/$repo/commits/$c" --jq '.commit.message|split("\n")[0]' 2>/dev/null || true)"
  echo "$c  $v ($st)  $msg"
done

if [ -n "${REPO_DIR:-}" ]; then
  echo; echo "== range-diff (all '=' rows: rebase only, no new code)"
  git -C "$REPO_DIR" fetch -q origin "$base" "+pull/$n/head:refs/rereview/$n" "$old" 2>/dev/null || git -C "$REPO_DIR" fetch -q origin "$base" "+pull/$n/head:refs/rereview/$n"
  ob="$(git -C "$REPO_DIR" merge-base "origin/$base" "$old")"; nb="$(git -C "$REPO_DIR" merge-base "origin/$base" "$head")"
  git -C "$REPO_DIR" range-diff -s "$ob..$old" "$nb..$head" | cat
  git -C "$REPO_DIR" update-ref -d "refs/rereview/$n"
fi
