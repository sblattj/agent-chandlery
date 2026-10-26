#!/bin/zsh
# Reply to and resolve review threads, bring the branch current, then merge (or arm auto-merge) a GitHub PR.
# Usage: land.sh <pr> [-R owner/repo] [--replies replies.json] [--resolve-unreplied] [--wait SECS=600] [--dry-run]
#   replies.json: [{"cid":"<first comment databaseId of the thread>","body":"markdown"}]
# Exit: 0 merged (or armed with --wait 0) | 2 unresolved threads with no reply | 3 conflicts | 4 not merged in time | 5 bad state
set -euo pipefail
PR=${1:-}; [[ $PR == <-> ]] || { sed -n "2,5p" $0; exit 5; }; shift; R=""; REPLIES=""; FORCE=0; WAIT=600; DRY=0
while (( $# )); do case $1 in
  -R) R=$2; shift 2;; --replies) REPLIES=$2; shift 2;; --resolve-unreplied) FORCE=1; shift;;
  --wait) WAIT=$2; shift 2;; --dry-run) DRY=1; shift;; *) print -u2 "unknown arg $1"; exit 5;; esac; done
[[ -n $R ]] || R=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
O=${R%/*}; N=${R#*/}; GR=(-R $R)
LOG=${LOG:-/tmp/land-pr/$N-$PR.log}; mkdir -p ${LOG:h}
say() { print -r -- "$(date +%T) $*" | tee -a $LOG; }
run() { if (( DRY )); then say "DRY: $*"; else "$@"; fi; }
me=$(gh api user --jq .login)

retry() { local i; for i in 1 2 3 4 5; do "$@" && return 0; say "retry $i: $1 failed (transient API error?)"; sleep $((i*5)); done; return 1; }
pr() { retry gh pr view $PR $GR --json state,isDraft,mergeable,mergeStateStatus,reviewDecision,headRefOid,baseRefName,autoMergeRequest; }
s=$(pr); say "PR $R#$PR as $me: $(jq -c '{state,isDraft,mergeable,mergeStateStatus,reviewDecision}' <<<$s)"
[[ $(jq -r .state <<<$s) == MERGED ]] && { say "already merged"; exit 0; }
[[ $(jq -r .state <<<$s) == OPEN ]] || { say "not open"; exit 5; }
[[ $(jq -r .isDraft <<<$s) == false ]] || { say "draft: mark ready first (gh pr ready)"; (( DRY )) || exit 5; }

# 1. conflicts / behind
case $(jq -r .mergeable <<<$s) in
  CONFLICTING) say "CONFLICTS with $(jq -r .baseRefName <<<$s): merge the base in a worktree, resolve, test, push, rerun"; exit 3;;
esac
if [[ $(jq -r .mergeStateStatus <<<$s) == BEHIND ]]; then say "behind base: update-branch"; run gh pr update-branch $PR $GR | tee -a $LOG; fi

# 2. threads
threads() { gh api graphql -f query='query($o:String!,$n:String!,$p:Int!){repository(owner:$o,name:$n){pullRequest(number:$p){reviewThreads(first:100){nodes{id isResolved isOutdated comments(first:50){nodes{databaseId url author{login}}}}}}}}' -f o=$O -f n=$N -F p=$PR \
  --jq '[.data.repository.pullRequest.reviewThreads.nodes[]|select(.isResolved|not)|{id,isOutdated,cid:(.comments.nodes[0].databaseId|tostring),url:.comments.nodes[0].url,by:.comments.nodes[0].author.login,last:.comments.nodes[-1].author.login}]'; }
T=$(threads); say "unresolved threads: $(jq length <<<$T)"
missing=()
for row in ${(f)"$(jq -c '.[]' <<<$T)"}; do
  id=$(jq -r .id <<<$row); cid=$(jq -r .cid <<<$row); url=$(jq -r .url <<<$row); last=$(jq -r .last <<<$row)
  body=""; [[ -n $REPLIES ]] && body=$(jq -r --arg c $cid '.[]|select(.cid==$c)|.body' $REPLIES)
  if [[ -n $body ]]; then
    print -r -- $body > /tmp/land-pr/body.$cid
    (( DRY )) && say "DRY: reply $url" || say "replied $(gh api -X POST repos/$R/pulls/$PR/comments/$cid/replies -F body=@/tmp/land-pr/body.$cid --jq .html_url)"
  elif [[ $last != $me ]] && (( ! FORCE )); then missing+=$url; continue; fi
  run gh api graphql -f query="mutation{resolveReviewThread(input:{threadId:\"$id\"}){thread{isResolved}}}" --silent && say "resolved $url"
done
(( ${#missing} )) && { say "NO REPLY (draft one per thread, pass --replies): ${(j: :)missing}"; exit 2; }

# 3. merge: direct, else auto-merge with the repo's allowed method
m=$(gh api repos/$R --jq 'if .allow_squash_merge then "squash" elif .allow_merge_commit then "merge" else "rebase" end')
(( DRY )) && { say "DRY: gh pr merge --$m (then --auto)"; exit 0; }
if gh pr merge $PR $GR --$m 2>>$LOG; then say "merged ($m)"; else
  say "direct merge refused, arming auto-merge"; gh pr merge $PR $GR --$m --auto 2>&1 | tee -a $LOG; fi
end=$((SECONDS+WAIT))
while (( SECONDS < end )); do s=$(pr); [[ $(jq -r .state <<<$s) == MERGED ]] && break; sleep 15; done
s=$(retry gh pr view $PR $GR --json state,mergeStateStatus,mergeCommit,reviewDecision,statusCheckRollup)
if [[ $(jq -r .state <<<$s) == MERGED ]]; then say "MERGED $(jq -r .mergeCommit.oid <<<$s)"; exit 0; fi
say "not merged yet: $(jq -c '{mergeStateStatus,reviewDecision,failing:[.statusCheckRollup[]|select((.conclusion//.state)|test("FAIL|ERROR|CANCEL"))|.name//.context],pending:[.statusCheckRollup[]|select((.status//"")|test("PROGRESS|QUEUED|PENDING"))|.name]}' <<<$s)"
(( WAIT == 0 )) && exit 0 || exit 4
