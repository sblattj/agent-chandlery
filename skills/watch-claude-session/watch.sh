#!/usr/bin/env bash
# Watch another Claude Code session's transcript.
#   watch.sh find  [repo-dir|uuid]        # print the newest transcript path (default: cwd)
#   watch.sh catchup [repo-dir|uuid] [N]  # last N tool calls (default 40) + user prompts
#   watch.sh live  [repo-dir|uuid]        # stream USER/CLAUDE/TOOL/TOOL_ERR lines from now on
# Read-only. WIDTH=220 trims each line.
set -euo pipefail
MODE="${1:-find}"; ARG="${2:-$PWD}"; N="${3:-40}"; W="${WIDTH:-220}"
P=~/.claude/projects

resolve() {
  local a="$1"
  if [[ "$a" =~ ^[0-9a-f]{8}-[0-9a-f-]{27}$ ]]; then
    ls -t $P/*/"$a".jsonl 2>/dev/null | head -1; return
  fi
  a="$(cd "$a" 2>/dev/null && pwd -P || echo "$a")"
  local d="$P/$(echo "$a" | sed 's#[/.]#-#g')"
  [ -d "$d" ] || { echo "no project dir: $d" >&2; return 1; }
  ls -t "$d"/*.jsonl 2>/dev/null | head -1
}

F="$(resolve "$ARG")"; [ -n "$F" ] || { echo "no transcript for $ARG" >&2; exit 1; }

FILTER='def c(s): (s|tostring|gsub("\\s+";" "))[0:'"$W"'];
  if .type=="user" and (.message.content|type)=="string" then "USER: "+c(.message.content)
  elif .type=="user" then (.message.content[]? | select(.type=="tool_result" and .is_error==true) | "TOOL_ERR: "+c(.content))
  elif .type=="assistant" then (.message.content[]? |
     if .type=="text" then "CLAUDE: "+c(.text)
     elif .type=="tool_use" then "TOOL "+.name+": "+c(.input.command // .input.description // .input.file_path // (.input|tojson))
     else empty end)
  else empty end'

case "$MODE" in
  find)    echo "$F"; ls -l "$F" | awk '{print $6, $7, $8}' ;;
  catchup) echo "# $F"; jq -r "$FILTER" "$F" 2>/dev/null | grep -v '^CLAUDE: ' | tail -n "$N" ;;
  live)    echo "# $F" >&2; tail -n 0 -F "$F" | jq --unbuffered -r "$FILTER" 2>/dev/null ;;
  *) echo "usage: watch.sh find|catchup|live [repo-dir|uuid] [N]" >&2; exit 2 ;;
esac
