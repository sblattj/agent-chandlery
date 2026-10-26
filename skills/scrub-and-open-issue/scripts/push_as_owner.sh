#!/usr/bin/env bash
# Push a branch, or open a PR, on a repo owned by a personal account, AS THAT
# OWNER, never the active (company) gh account. Same hard gate as open_issue.sh:
# if gh cannot act as the owner, nothing is pushed or created.
#
# Usage (run inside the git checkout):
#   push_as_owner.sh push  [--repo OWNER/REPO] [--remote origin] [--check-only] [REFSPEC...]
#   push_as_owner.sh pr    [--repo OWNER/REPO] --title T --body-file F [--base main] [--head BRANCH] [--check-only]
#   push_as_owner.sh check [--repo OWNER/REPO]          # gate only, prints who would act
#
# push with no REFSPEC pushes the current branch (-u). Typical use:
#   push_as_owner.sh push                      # branch
#   push_as_owner.sh push mybranch:main        # fast-forward main (the "merge" for personal repos)
#
# Before pushing it also refuses if any commit about to go up has a committer or
# author email on a blocked domain, or if the branch name fails leak_lint.py.
# Never changes the active gh account; the token is scoped to this one git/gh
# call through the environment (not argv).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BLOCKED="${SCRUB_BLOCKED_AUTHORS:-$HOME/.config/scrub/blocked-authors.txt}"
BLOCKLISTS=("$HERE/../reference/blocked-authors.txt" "$LOCAL_BLOCKED")
LINT="$HERE/leak_lint.py"
# Blocked commit email patterns live in a local-only file (never committed).
EMAIL_FILE="${SCRUB_BLOCKED_EMAILS:-$HOME/.config/scrub/blocked-email-domains.txt}"
BLOCKED_EMAIL_RE=""
if [[ -f "$EMAIL_FILE" ]]; then
  BLOCKED_EMAIL_RE="$(sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$EMAIL_FILE" | grep -v '^$' | paste -sd '|' - || true)"
else
  echo "warning: $EMAIL_FILE not found; commit emails will not be checked against a company-domain list." >&2
fi

die() { echo "REFUSED: $*" >&2; exit 1; }

cmd="${1:-}"; shift || true
[[ "$cmd" =~ ^(push|pr|check)$ ]] || { sed -n 2,20p "$0"; exit 2; }

repo=""; remote="origin"; check_only=0; title=""; body_file=""; base=""; head=""
refspecs=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2;;
    --remote) remote="$2"; shift 2;;
    --title) title="$2"; shift 2;;
    --body-file) body_file="$2"; shift 2;;
    --base) base="$2"; shift 2;;
    --head) head="$2"; shift 2;;
    --check-only) check_only=1; shift;;
    --*) die "unknown arg: $1";;
    *) refspecs+=("$1"); shift;;
  esac
done

# Resolve OWNER/REPO from the remote when not given.
if [[ -z "$repo" ]]; then
  url="$(git remote get-url "$remote" 2>/dev/null || true)"
  [[ -n "$url" ]] || die "no --repo and no git remote '$remote' here"
  repo="$(echo "$url" | sed -E 's#^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)##; s#\.git$##')"
fi
[[ "$repo" == */* ]] || die "cannot resolve OWNER/REPO from '$repo'"
owner="${repo%%/*}"

# Blocklist gate on the owner we are about to act as.
[[ -f "$LOCAL_BLOCKED" ]] || echo "warning: local blocked-authors file not found at $LOCAL_BLOCKED; only the owner gate applies." >&2
for BLOCKLIST in "${BLOCKLISTS[@]}"; do
  [[ -f "$BLOCKLIST" ]] || continue
  while IFS= read -r line; do
    line="${line%%#*}"; line="$(echo "$line" | xargs 2>/dev/null || true)"
    [[ -z "$line" ]] && continue
    [[ "$(echo "$line" | tr 'A-Z' 'a-z')" == "$(echo "$owner" | tr 'A-Z' 'a-z')" ]] && die "owner '$owner' is on the blocked-authors list."
  done < "$BLOCKLIST"
done

token="$(gh auth token --user "$owner" 2>/dev/null || true)"
[[ -n "$token" ]] || die "gh is not authenticated as '$owner'. Nothing pushed."
actual="$(GH_TOKEN="$token" gh api user --jq .login 2>/dev/null || true)"
[[ "$actual" == "$owner" ]] || die "token for '$owner' resolved to '$actual'. Aborting."
owner_type="$(GH_TOKEN="$token" gh api "repos/$repo" --jq '.owner.type' 2>/dev/null || true)"
[[ "$owner_type" == "User" ]] || die "$repo owner type is '${owner_type:-unknown}'; this script only acts on personal (User) repos."

active="$(gh api user --jq .login 2>/dev/null || echo '?')"
echo "gate OK: acting on $repo as '$owner' (active gh account '$active' is NOT used)"
[[ "$cmd" == "check" ]] && exit 0

export GH_TOKEN="$token"
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=""
export GIT_CONFIG_KEY_1=credential.helper
export GIT_CONFIG_VALUE_1='!f() { echo "username=x-access-token"; printf "%s=%s\n" password "$GH_TOKEN"; }; f'

if [[ "$cmd" == "push" ]]; then
  if [[ ${#refspecs[@]} -eq 0 ]]; then
    cur="$(git branch --show-current)"; [[ -n "$cur" ]] || die "detached HEAD; give a REFSPEC"
    refspecs=("$cur"); set_upstream=(-u)
  else
    set_upstream=()
  fi
  # Commits about to go up: blocked emails and branch-name leaks.
  for rs in "${refspecs[@]}"; do
    src="${rs%%:*}"; dst="${rs#*:}"; [[ "$rs" == *:* ]] || dst="$src"
    src="${src#+}"
    t="$(mktemp)"; printf '%s\n%s\n' "$src" "$dst" > "$t"
    python3 "$LINT" "$t" >/dev/null 2>&1 || { python3 "$LINT" "$t" >&2 || true; rm -f "$t"; die "refspec '$rs' fails leak_lint"; }
    rm -f "$t"
    default="$(gh api "repos/$repo" --jq .default_branch)"
    git fetch -q "$remote" "$dst" 2>/dev/null || git fetch -q "$remote" "$default" 2>/dev/null || true
    if git rev-parse -q --verify "refs/remotes/$remote/$dst" >/dev/null 2>&1; then range="$remote/$dst..$src"
    elif git rev-parse -q --verify "refs/remotes/$remote/$default" >/dev/null 2>&1; then range="$remote/$default..$src"
    else range="$src"; fi
    bad=""
    [[ -z "$BLOCKED_EMAIL_RE" ]] || bad="$(git log --format='%h %ae %ce' "$range" 2>/dev/null | grep -iE "$BLOCKED_EMAIL_RE" || true)"
    [[ -z "$bad" ]] || die "commits with a blocked author/committer email would be pushed:"$'\n'"$bad"
    n="$(git rev-list --count "$range" 2>/dev/null || echo '?')"
    echo "push $rs: $n commit(s)"
  done
  [[ "$check_only" == "1" ]] && { echo "check-only: not pushed"; exit 0; }
  git push ${set_upstream[@]+"${set_upstream[@]}"} "$remote" "${refspecs[@]}"
  echo "pushed as: $owner"
  exit 0
fi

# pr
[[ -n "$title" ]] || die "pr needs --title"
[[ -n "$body_file" && -f "$body_file" ]] || die "pr needs --body-file F"
head="${head:-$(git branch --show-current)}"; [[ -n "$head" ]] || die "pr needs --head"
base="${base:-$(gh api "repos/$repo" --jq .default_branch)}"
t="$(mktemp)"; printf '%s\n%s\n' "$title" "$head" > "$t"
python3 "$LINT" "$t" "$body_file" >/dev/null 2>&1 || { python3 "$LINT" "$t" "$body_file" >&2 || true; rm -f "$t"; die "PR title/head/body fails leak_lint"; }
rm -f "$t"
[[ "$check_only" == "1" ]] && { echo "check-only: would open PR $head -> $base on $repo as $owner"; exit 0; }
url="$(gh pr create -R "$repo" --head "$head" --base "$base" --title "$title" --body-file "$body_file")"
echo "Created: $url"
echo "Authored by: $(gh api "repos/$repo/pulls/${url##*/}" --jq .user.login)"
