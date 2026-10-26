#!/usr/bin/env bash
# Read-only helper for stacked PRs. Prints commands; never pushes, merges or rebases.
#   stack.sh plan <branch1> <branch2> ...          gh pr create lines, each based on the one below
#   stack.sh restack <child-branch> <oldTip|PR#>   after the lower PR merged: which fix, exact commands
# Env: BASE (default: origin's default branch), REMOTE (default: origin)
set -euo pipefail
REMOTE=${REMOTE:-origin}
base() {
  [[ -n "${BASE:-}" ]] && { echo "$BASE"; return; }
  git symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null | sed "s#^$REMOTE/##" || echo main
}
usage() { sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

cmd=${1:-}; shift || true
case "$cmd" in
plan)
  (( $# >= 1 )) || usage
  prev=$(base)
  echo "# Open bottom-up. Each PR's base = the branch below it."
  for b in "$@"; do
    echo "git push -u $REMOTE $b && gh pr create --head $b --base $prev --fill"
    prev=$b
  done
  echo
  echo "# Once per repo, so GitHub retargets the next PR when the lower branch is deleted:"
  echo "gh repo edit --delete-branch-on-merge"
  echo "# Merge order: $(base) <- $* (bottom first). Never merge an upper PR first."
  ;;
restack)
  (( $# == 2 )) || usage
  child=$1; tip=$2; b=$(base)
  if [[ "$tip" =~ ^[0-9]+$ ]]; then
    tip=$(gh pr view "$tip" --json headRefOid --jq .headRefOid)   # merged PR keeps its last head SHA
  fi
  git fetch -q "$REMOTE" "$b"
  git cat-file -e "$tip^{commit}" 2>/dev/null || git fetch -q "$REMOTE" "$tip" || { echo "old tip $tip not found locally or on $REMOTE" >&2; exit 1; }
  up="$REMOTE/$b"
  short=$(git rev-parse --short "$tip")
  echo "child: $child   old lower tip: $short   base: $up"
  echo "diff now ($up...$child):"; git diff --stat "$up...$child" | sed 's/^/  /'
  if git merge-base --is-ancestor "$tip" "$up"; then
    echo "=> merge commit: lower PR's commits are on $b. Nothing to do."
  elif cherry=$(git cherry "$up" "$tip" "$(git merge-base "$up" "$tip")") && [[ "$cherry" != *"+ "* ]]; then
    echo "=> rebase-merge: $b has patch-identical copies. Plain rebase drops them:"
    echo "   git switch $child && git rebase $up && git push --force-with-lease $REMOTE $child"
  else
    echo "=> squash (or edited) merge: plain rebase would conflict. Cut at the old tip:"
    echo "   git switch $child && git rebase --onto $up $short $child && git push --force-with-lease $REMOTE $child"
  fi
  echo "   no-force-push alternative (may conflict if both PRs touched the same lines):"
  echo "   git switch $child && git merge $up && git push $REMOTE $child"
  ;;
*) usage ;;
esac
