#!/usr/bin/env bash
# Open a GitHub issue authored by the target repo's OWNER account, never a
# blocked/company account. Hard gate: if gh cannot act as the required author,
# nothing is created.
#
# Usage:
#   open_issue.sh --repo OWNER/REPO --title-file F --body-file F \
#       [--author LOGIN] [--label L]... [--check-only]
#
# Does NOT change your active gh account. It scopes identity per-command with
# GH_TOKEN via `gh auth token --user <login>`.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Blocked authors: shareable reference list + local-only list (never committed).
LOCAL_BLOCKED="${SCRUB_BLOCKED_AUTHORS:-$HOME/.config/scrub/blocked-authors.txt}"
BLOCKLISTS=("$HERE/../reference/blocked-authors.txt" "$LOCAL_BLOCKED")

repo=""; title_file=""; body_file=""; author=""; check_only=0
labels=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2;;
    --title-file) title_file="$2"; shift 2;;
    --body-file) body_file="$2"; shift 2;;
    --author) author="$2"; shift 2;;
    --label) labels+=("$2"); shift 2;;
    --check-only) check_only=1; shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

die() { echo "REFUSED: $*" >&2; exit 1; }

[[ -n "$repo" ]] || die "missing --repo OWNER/REPO"
[[ "$repo" == */* ]] || die "--repo must be OWNER/REPO, got '$repo'"
[[ -n "$title_file" && -f "$title_file" ]] || die "missing/invalid --title-file"
[[ -n "$body_file"  && -f "$body_file"  ]] || die "missing/invalid --body-file"

owner="${repo%%/*}"

# Prefer the owner's own token to read metadata (resolves private personal repos).
meta_token=""
if gh auth token --user "$owner" >/dev/null 2>&1; then
  meta_token="$(gh auth token --user "$owner" 2>/dev/null)"
fi

owner_type="$(GH_TOKEN="$meta_token" gh api "repos/$repo" --jq '.owner.type' 2>/dev/null || true)"
[[ -n "$owner_type" ]] || die "cannot resolve $repo (not found, or no gh account can see it)."

# Resolve the required author.
if [[ -z "$author" ]]; then
  if [[ "$owner_type" == "User" ]]; then
    author="$owner"
  else
    die "$repo is owned by an organization ($owner). A GitHub issue cannot be authored as an org. Re-run with --author <login> naming a specific authenticated, non-blocked account, confirmed with the user."
  fi
fi

# Blocklist gate.
[[ -f "$LOCAL_BLOCKED" ]] || echo "warning: local blocked-authors file not found at $LOCAL_BLOCKED; only the owner gate applies." >&2
for BLOCKLIST in "${BLOCKLISTS[@]}"; do
  [[ -f "$BLOCKLIST" ]] || continue
  while IFS= read -r line; do
    line="${line%%#*}"; line="$(echo "$line" | xargs 2>/dev/null || true)"
    [[ -z "$line" ]] && continue
    if [[ "$(echo "$line" | tr 'A-Z' 'a-z')" == "$(echo "$author" | tr 'A-Z' 'a-z')" ]]; then
      die "author '$author' is on the blocked-authors list. This account must never file issues."
    fi
  done < "$BLOCKLIST"
done

# Must have that account in gh.
token="$(gh auth token --user "$author" 2>/dev/null || true)"
[[ -n "$token" ]] || die "gh is not authenticated as '$author' (the required author). Add it (gh auth login) or do not file. No issue created."

# Verify the token really is that login.
actual="$(GH_TOKEN="$token" gh api user --jq .login 2>/dev/null || true)"
[[ "$actual" == "$author" ]] || die "token for '$author' resolved to '$actual'. Aborting for safety."

if [[ "$check_only" == "1" ]]; then
  echo "OK: would file on '$repo' (owner type: $owner_type) authored by '$author'."
  exit 0
fi

title="$(cat "$title_file")"
[[ -n "$title" ]] || die "empty title."

create_args=(-R "$repo" --title "$title" --body-file "$body_file")
for l in "${labels[@]}"; do create_args+=(--label "$l"); done

url="$(GH_TOKEN="$token" gh issue create "${create_args[@]}")"
echo "Created: $url"
echo "Authored by: $author"
