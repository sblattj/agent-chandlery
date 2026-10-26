#!/usr/bin/env bash
# Report activity on YOUR open non-draft PRs since your last commit push, and
# whether you have already responded to each item.
#
# "Activity" = anything a *different* person did after your latest commit:
# a review, a review (inline) comment, or a conversation comment.
#
# Each item is tagged:
#   AWAITING-YOU              nothing from you after it (no comment, review reply, or push)
#   you-responded <ts>        you commented / reviewed / pushed after it
#   you-responded in-thread   (inline comments) you replied inside that diff thread
#   you-responded elsewhere   (inline comments) you responded, but not in that thread
#
# Also flags STALE change-requests: a reviewer's standing CHANGES_REQUESTED that
# you already answered (comment or push after it) but they have not re-reviewed.
#
# Read-only. Never re-requests review (that would reset a standing approval).
#
# Usage:  pr-activity.sh [REPO]
#   REPO defaults to the current repo (gh repo view), else $PR_ACTIVITY_REPO.
#   Env:  PR_ACTIVITY_REPO (fallback repo)   AUTHOR=@me (default)   SINCE=<ISO8601 override anchor, optional>
set -euo pipefail

REPO="${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo "${PR_ACTIVITY_REPO:-}")}"
[ -n "$REPO" ] || { echo "error: no repo: pass OWNER/REPO, run inside a repo, or set PR_ACTIVITY_REPO" >&2; exit 2; }
AUTHOR="${AUTHOR:-@me}"
ME="$(gh api user --jq .login)"

mapfile -t rows < <(
  gh pr list --repo "$REPO" --author "$AUTHOR" --draft=false --state open \
    --json number,title,reviewDecision,mergeable,mergeStateStatus \
    --jq '.[] | [.number, .title, (.reviewDecision // "NONE"), .mergeable, .mergeStateStatus] | @tsv'
)

if [ "${#rows[@]}" -eq 0 ]; then
  echo "No open non-draft PRs by $ME on $REPO."
  exit 0
fi

# Flatten a `gh api --paginate --slurp` result (array of pages) into one array.
# gh's own --jq cannot be combined with --slurp, so pipe to external jq.
fetch_all() { gh api "$1" --paginate --slurp 2>/dev/null | jq -c '[.[][]]' || echo '[]'; }

# One jq program per PR. Inputs: $r reviews, $c inline comments, $i convo
# comments, $pv (commits + latestReviews), $me, $t (anchor).
# ISO-8601 "...Z" timestamps compare lexicographically = chronologically.
read -r -d '' JQ_PROG <<'JQ' || true
def pad($n): . + (" " * $n) | .[0:$n];

# Every timestamp at which YOU did something on this PR (comment, review, push).
def mine_times:
  [ ($r[] | select(.user.login==$me and .submitted_at!=null) | .submitted_at),
    ($c[] | select(.user.login==$me) | .created_at),
    ($i[] | select(.user.login==$me) | .created_at),
    ($pv.commits[]? | .committedDate) ]
  | map(select(. != null)) | sort;

def my_inline_replies:
  [ $c[] | select(.user.login==$me)
    | {thread: ((.in_reply_to_id // .id)|tostring), at: .created_at} ];

# Earliest response of yours strictly after $ts, or null.
def responded_after($ts): [ mine_times[] | select(. > $ts) ] | sort | .[0];

# Per-author latest opinionated review (APPROVED / CHANGES_REQUESTED) from the
# full REST list. Do NOT trust `gh pr view --json latestReviews`: it has been
# observed to drop a standing CHANGES_REQUESTED entirely.
def latest_opinionated:
  [ $r[] | select(.submitted_at!=null and .user.login != $me
                  and (.state=="APPROVED" or .state=="CHANGES_REQUESTED")) ]
  | group_by(.user.login) | map(sort_by(.submitted_at) | last);

def approvals: [ latest_opinionated[] | select(.state=="APPROVED") ] | length;

# A bare approval (no body) needs no reply from you; everything else does.
def items:
  [ ($r[] | select(.submitted_at!=null and .submitted_at > $t and .user.login != $me)
      | {kind:"review", sub:.state, user:.user.login, ts:.submitted_at, extra:"", thread:null,
         needs: (.state != "APPROVED" and .state != "DISMISSED" or ((.body // "") | length) > 0)}),
    ($c[] | select(.created_at > $t and .user.login != $me)
      | {kind:"comment", sub:"inline", user:.user.login, ts:.created_at, extra:.path,
         thread:((.in_reply_to_id // .id)|tostring), needs:true}),
    ($i[] | select(.created_at > $t and .user.login != $me)
      | {kind:"comment", sub:"convo", user:.user.login, ts:.created_at, extra:"", thread:null, needs:true}) ]
  | sort_by(.ts);

def status:
  . as $it
  | if ($it.needs|not) then "fyi, no reply needed"
    elif $it.thread != null then
      ([my_inline_replies[] | select(.thread==$it.thread and .at > $it.ts) | .at] | sort | .[0]) as $in
      | if $in then "you-responded in-thread \($in)"
        else (responded_after($it.ts)) as $g
          | if $g then "you-responded elsewhere \($g)" else "AWAITING-YOU" end
        end
    else (responded_after($it.ts)) as $g
      | if $g then "you-responded \($g)" else "AWAITING-YOU" end
    end;

def line:
  "  \(.kind|pad(8)) \(.sub|pad(18)) \(.user|pad(22)) \(.ts)  [\(status)]"
  + (if .extra != "" then "  \(.extra)" else "" end);

# Standing CHANGES_REQUESTED (per-author latest) that you answered after it was left.
def stale_cr:
  [ latest_opinionated[] | select(.state=="CHANGES_REQUESTED")
    | . as $cr | (responded_after($cr.submitted_at)) as $g | select($g != null)
    | "  ~ stale changes-request: \($cr.user.login) at \($cr.submitted_at); you responded \($g); needs their re-review" ];

items as $its
| ($its | map(select((status|startswith("AWAITING")))) | length) as $await
| "AWAITING=\($await) ITEMS=\($its|length) APPROVALS=\(approvals)",
  ($its[] | line),
  (stale_cr[])
JQ

echo "Activity since your last push, $ME on $REPO"
echo

awaiting_prs=()
stale_prs=()
ci_fail_prs=()
ci_pending_prs=()
conflict_prs=()

for row in "${rows[@]}"; do
  IFS=$'\t' read -r num title decision mergeable mstate <<<"$row"

  # Anchor = latest commit's committedDate (proxy for "your last push";
  # a review can only land after the push, so this is a safe lower bound).
  # Also pull the CI rollup + conflict state on the same view call: a green
  # review means nothing if CI is red or the branch conflicts, and both are
  # things that await YOU (fix the build / resolve the conflict), not a reviewer.
  pv="$(gh pr view "$num" --repo "$REPO" --json commits,statusCheckRollup,mergeable,mergeStateStatus 2>/dev/null || echo '{}')"
  T="${SINCE:-$(jq -r '.commits[-1].committedDate // empty' <<<"$pv")}"

  if [ -z "$T" ]; then
    printf '#%s  %s\n' "$num" "$title"
    echo "   ! could not determine last-push time; skipping activity scan"
    echo
    continue
  fi

  # CI rollup: RED (any failing/cancelled/action-required context, named),
  # pending (queued/in-progress/expected), or green. `skipping` contexts are
  # path-filtered and count as neither fail nor pending. StatusContext uses
  # .context/.state; CheckRun uses .name/.status/.conclusion.
  ci="$(jq -r '
    (.statusCheckRollup // []) as $c
    | [ $c[] | select(((.conclusion//"")|test("FAILURE|TIMED_OUT|CANCELLED|ACTION_REQUIRED"))
                      or ((.state//"")|test("^FAILURE$|^ERROR$"))) | (.name // .context) ] as $fail
    | ([ $c[] | select(((.status//"")|test("QUEUED|IN_PROGRESS|PENDING|WAITING"))
                      or ((.state//"")|test("^PENDING$|^EXPECTED$"))) ] | length) as $pend
    | if ($fail|length) > 0 then "RED " + ($fail|unique|join(","))
      elif $pend > 0 then "pending(\($pend))"
      else "green" end' <<<"$pv" 2>/dev/null || echo "unknown")"
  # Fresher conflict state from the view (falls back to the list values).
  mv="$(jq -r '.mergeable // empty' <<<"$pv")";      [ -n "$mv" ] && mergeable="$mv"
  ms="$(jq -r '.mergeStateStatus // empty' <<<"$pv")"; [ -n "$ms" ] && mstate="$ms"
  conflict=""; case "$mergeable/$mstate" in CONFLICTING/*|*/DIRTY|*/CONFLICTING) conflict="yes";; esac

  # Three endpoints or you miss activity: reviews, inline diff comments, conversation comments.
  r_json="$(fetch_all "repos/$REPO/pulls/$num/reviews")"
  c_json="$(fetch_all "repos/$REPO/pulls/$num/comments")"
  i_json="$(fetch_all "repos/$REPO/issues/$num/comments")"

  out="$(jq -r -n --arg me "$ME" --arg t "$T" \
          --argjson r "$r_json" --argjson c "$c_json" --argjson i "$i_json" --argjson pv "$pv" \
          "$JQ_PROG")"

  hdr="$(head -n1 <<<"$out")"
  body="$(tail -n +2 <<<"$out")"
  await="${hdr#AWAITING=}"; await="${await%% *}"
  total="${hdr##*ITEMS=}"; total="${total%% *}"
  appr="${hdr##*APPROVALS=}"

  printf '#%s  %s\n' "$num" "$title"
  printf '   last push %s | review: %s | approvals: %s | %s/%s | CI: %s%s\n' \
    "$T" "$decision" "$appr" "$mergeable" "$mstate" "$ci" \
    "$([ -n "$conflict" ] && echo ' | MERGE CONFLICT')"

  if [ "$total" -gt 0 ]; then
    printf '   >> %s new item(s) since your push, %s awaiting you:\n' "$total" "$await"
    printf '%s\n' "$body"
  else
    echo "   -- no activity since your push"
    [ -n "$body" ] && printf '%s\n' "$body"
  fi

  [ "$await" -gt 0 ] && awaiting_prs+=("#$num")
  grep -q 'stale changes-request' <<<"$body" && stale_prs+=("#$num")
  case "$ci" in RED*) ci_fail_prs+=("#$num");; pending*) ci_pending_prs+=("#$num");; esac
  [ -n "$conflict" ] && conflict_prs+=("#$num")
  echo
done

echo "Summary"
if [ "${#awaiting_prs[@]}" -gt 0 ]; then
  echo "  Awaiting you (reviews):  ${awaiting_prs[*]}"
else
  echo "  Awaiting you (reviews):  none"
fi
[ "${#ci_fail_prs[@]}"    -gt 0 ] && echo "  CI FAILING (fix build):  ${ci_fail_prs[*]}"
[ "${#conflict_prs[@]}"   -gt 0 ] && echo "  MERGE CONFLICT (resolve):${conflict_prs[*]}"
[ "${#ci_pending_prs[@]}" -gt 0 ] && echo "  CI still running:        ${ci_pending_prs[*]}"
if [ "${#stale_prs[@]}" -gt 0 ]; then
  echo "  Stale changes-requested: ${stale_prs[*]}  (you answered; reviewer has not re-reviewed)"
fi
if [ "${#ci_fail_prs[@]}" -eq 0 ] && [ "${#conflict_prs[@]}" -eq 0 ]; then
  echo "  Conflicts & CI:          all conflict-free, no failing CI"
fi
