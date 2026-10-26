#!/bin/bash
# What does a Kiro CLI agent load into context? Runs one headless V3 chat in a fresh dir, finds ITS session by
# workspacePaths (not ls -t: another live session wins that), and prints every steering/resource doc it loaded.
# usage: probe.sh [--agent NAME] [--engine v3|v2] [--recall] [--mark TEXT...]
#   --recall  also asks the model what your instructions say (works on v2, whose session log has no steering)
#   --mark    count extra strings in the session (canaries, headings), e.g. --mark CANARY_X "## My rules"
# env: PROBE_TIMEOUT (300). Read-only apart from the chat session it creates.
set -u
agent=""; engine=v3; recall=0; marks=()
while [ $# -gt 0 ]; do case $1 in
  --agent) agent=$2; shift 2 ;; --engine) engine=$2; shift 2 ;; --recall) recall=1; shift ;;
  --mark) shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do marks+=("$1"); shift; done ;;
  *) echo "unknown arg $1" >&2; exit 2 ;; esac; done
dir=$(mktemp -d /tmp/kiro-probe.XXXXXX); real=$(cd "$dir" && pwd -P); cd "$dir" || exit 1
ag=(); [ -n "$agent" ] && ag=(--agent "$agent")
q="Reply with just OK."
[ $recall = 1 ] && q="From your loaded instructions only (no tools): what is my name, and where do I work? If your instructions do not say, reply UNKNOWN."
perl -e 'alarm shift; exec @ARGV' "${PROBE_TIMEOUT:-300}" kiro-cli chat --agent-engine "$engine" --no-interactive ${ag[@]+"${ag[@]}"} "$q" > out.txt 2>&1 || echo "kiro-cli exit $?"
echo "agent=${agent:-<default>} engine=$engine dir=$real"
echo "reply: $(grep -v '^\[INFO\]' out.txt | tail -1)"
if [ "$engine" != v3 ]; then echo "(v2 logs no steering content: use --recall)"; exit 0; fi
s=$(grep -l "\"$real\"" ~/.kiro/sessions/*/sess_*/session.json 2>/dev/null | head -1)
[ -n "$s" ] || { echo "no V3 session found for $real"; exit 1; }
d=${s%/session.json}; echo "session: $d  agentMode=$(grep -o '"agentMode": *"[^"]*"' "$s" | cut -d'"' -f4)"
python3 -I - "$d" "${marks[@]+"${marks[@]}"}" <<'PY'
import json, re, sys, glob
d, marks = sys.argv[1], sys.argv[2:]
txt = ''.join(open(f).read() for f in [d + '/messages.jsonl'] + glob.glob(d + '/sub-executions/*.jsonl'))
docs = {}
for m in re.finditer(r'\{"id":"(file://[^"]+)","displayName":"[^"]*","content":"((?:[^"\\]|\\.)*)"', txt):
    docs[m.group(1)] = len(json.loads('"' + m.group(2) + '"'))
for i, n in sorted(docs.items(), key=lambda x: -x[1]): print(f"  {n:7d} chars  {i}")
print(f"  steering docs: {len(docs)}, {sum(docs.values())} chars (~{sum(docs.values())//4} tok)  [agent resources are not in this list; use --mark/--recall]")
for u in re.findall(r'\[Unresolved steering reference: [^\]]*\]', txt): print("  UNRESOLVED", u)
for k in marks: print(f"  mark {k!r}: {txt.count(k)}")
PY
