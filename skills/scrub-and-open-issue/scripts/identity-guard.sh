#!/usr/bin/env bash
# Keep a personal GitHub account's repos committing and pushing only as that account.
#   1. Clears repo-local user.name/user.email in every checkout whose origin is github.com/<owner>/...,
#      so a global includeIf (remote url github.com/<owner>/** -> a personal gitconfig) governs identity.
#   2. Records the expected identity as custom keys (identity-guard.owner / .email / .ours) in the repo's
#      config; these do not change who commits, they only tell the hooks what to enforce.
#   3. Symlinks the pre-commit and pre-push hooks from ./hooks into the common git dir, so every worktree
#      of the checkout shares them.
# Usage: identity-guard.sh --owner LOGIN --email EMAIL [--ours REGEX] [--roots "DIR ..."] [--check]
#   --email  the identity commits must carry, e.g. 12345+<login>@users.noreply.github.com
#   --ours   case-insensitive regex for "this commit is mine" in pre-push (default: the owner login).
#            Add your real-name parts so a commit made under a work identity is caught too.
#   --roots  parent dirs to scan, one level deep (default: "$HOME/dev $HOME/code $HOME/.wt"; .wt also two deep)
#   --check  report only, change nothing
# Env fallbacks: IDENTITY_GUARD_OWNER, IDENTITY_GUARD_EMAIL, IDENTITY_GUARD_OURS, IDENTITY_GUARD_ROOTS.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="$HERE/hooks"
MARK="identity-guard hook"
OWNER="${IDENTITY_GUARD_OWNER:-}"; EMAIL="${IDENTITY_GUARD_EMAIL:-}"; OURS="${IDENTITY_GUARD_OURS:-}"
ROOTS="${IDENTITY_GUARD_ROOTS:-$HOME/dev $HOME/code $HOME/.wt}"; CHECK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) OWNER="$2"; shift 2;;
    --email) EMAIL="$2"; shift 2;;
    --ours) OURS="$2"; shift 2;;
    --roots) ROOTS="$2"; shift 2;;
    --check) CHECK=1; shift;;
    -h|--help) sed -n 2,15p "$0"; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[[ -n "$OWNER" && -n "$EMAIL" ]] || { echo "need --owner LOGIN and --email EMAIL (see --help)" >&2; exit 2; }
OURS="${OURS:-$OWNER}"
seen=""
dirs=()
for r in $ROOTS; do
  for d in "$r"/*/ "$r"/*/*/; do [[ -e "$d/.git" ]] && dirs+=("$d"); done
done
for d in ${dirs[@]+"${dirs[@]}"}; do
  u=$(git -C "$d" remote get-url origin 2>/dev/null || true)
  case "$u" in *github.com[:/]"$OWNER"/*) ;; *) continue;; esac
  common=$(git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  case " $seen " in *" $common "*) continue;; esac; seen="$seen $common"
  ln=$(git -C "$d" config --local user.name || true); le=$(git -C "$d" config --local user.email || true)
  hp=$(git -C "$d" config core.hooksPath || true)
  hooks="$common/hooks"; [[ -n "$hp" ]] && hooks="$d/$hp"
  status="ok"
  if (( CHECK )); then
    [[ -z "$ln$le" ]] || status="local-identity($ln <$le>)"
    [[ "$(git -C "$d" config identity-guard.email || true)" == "$EMAIL" ]] || status="$status no-config"
    for h in pre-commit pre-push; do
      cmp -s "$TPL/$h" "$hooks/$h" || status="$status no-$h"
    done
  else
    [[ -z "$ln" ]] || git -C "$d" config --local --unset-all user.name
    [[ -z "$le" ]] || git -C "$d" config --local --unset-all user.email
    git -C "$d" config --local identity-guard.owner "$OWNER"
    git -C "$d" config --local identity-guard.email "$EMAIL"
    git -C "$d" config --local identity-guard.ours "$OURS"
    mkdir -p "$hooks"
    for h in pre-commit pre-push; do
      if [[ -f "$hooks/$h" ]] && ! grep -q "$MARK" "$hooks/$h"; then
        status="$status EXISTING-$h-left-alone(add guard by hand)"
      else
        ln -sf "$TPL/$h" "$hooks/$h"
      fi
    done
  fi
  eff=$(git -C "$d" var GIT_AUTHOR_IDENT | sed 's/ [0-9]* [-+][0-9]*$//')
  printf '%-55s %-50s %s\n' "$d" "$eff" "$status"
done
