#!/usr/bin/env bash
# find-concept.sh: locate where a design/code concept is defined, read-only.
# Bridges the prose name ("retry budget") to code identifiers (maxAttempts, RetryPolicy)
# by pulling backticked identifiers from doc lines that mention the phrase.
#
# Usage: find-concept.sh "<term>" [code_root] [docs_root] [-a alias ...]
#   roots: args, else CODE_ROOT/DOCS_ROOT env, else cwd git repo and its docs/
#   env: CODE_ROOT, DOCS_ROOT, MAX (hits per section, default 12), INCLUDE_TESTS=1
set -uo pipefail

term="${1:?usage: find-concept.sh \"<term>\" [code_root] [docs_root] [-a alias ...]}"; shift
_top="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
code_root="${CODE_ROOT:-$_top}"
docs_root="${DOCS_ROOT:-$_top/docs}"
[[ $# -gt 0 && "$1" != -a ]] && { code_root="$1"; shift; }
[[ $# -gt 0 && "$1" != -a ]] && { docs_root="$1"; shift; }
aliases=()
while [[ $# -gt 0 ]]; do [[ "$1" == -a ]] && { aliases+=("$2"); shift 2; } || shift; done
max="${MAX:-12}"

command -v rg >/dev/null || { echo "rg (ripgrep) is required" >&2; exit 2; }

# Spelling variants: "retry budget" -> retryBudget RetryBudget retry_budget RETRY_BUDGET retry-budget
variants() {
  python3 - "$1" <<'PY'
import sys, re
w = [x for x in re.split(r'[\s_\-]+', sys.argv[1].strip()) if x]
if not w: sys.exit()
lo = [x.lower() for x in w]
out = {" ".join(w), lo[0] + "".join(x.capitalize() for x in lo[1:]),
       "".join(x.capitalize() for x in lo), "_".join(lo), "_".join(lo).upper(), "-".join(lo)}
print("\n".join(sorted(out)))
PY
}

code_globs=(--glob '*.java' --glob '*.kt' --glob '*.ts' --glob '*.tsx' --glob '*.py' --glob '*.go'
            --glob '*.yaml' --glob '*.yml' --glob '!**/node_modules/**' --glob '!**/build/**' --glob '!**/target/**')
[[ "${INCLUDE_TESTS:-0}" == 1 ]] || code_globs+=(--glob '!**/src/test/**' --glob '!**/*.test.*' --glob '!**/*Test.java')
doc_globs=(--glob '*.md' --glob '!_superseded/**' --glob '!**/_superseded/**' --glob '!~$*')

pattern=$( { variants "$term"; for a in "${aliases[@]:-}"; do [[ -n "$a" ]] && variants "$a"; done; } \
  | python3 -c 'import sys,re; print("|".join(re.escape(l.strip()) for l in sys.stdin if l.strip()))')

echo "## Concept: $term"
[[ ${#aliases[@]} -gt 0 && -n "${aliases[0]:-}" ]] && echo "aliases: ${aliases[*]}"
if git -C "$code_root" rev-parse --git-dir >/dev/null 2>&1; then
  echo "code: $code_root @ $(git -C "$code_root" rev-parse --short HEAD) ($(git -C "$code_root" branch --show-current))"
else
  echo "code: $code_root (not a git repo or missing)"
fi
echo "docs: $docs_root"
[[ -f "$docs_root/AUTHORITY.md" ]] && echo "NOTE: $docs_root/AUTHORITY.md exists: code wins over docs; skip superseded docs."
echo

echo "### Docs mentioning it (files by hit count)"
if [[ -d "$docs_root" ]]; then
  rg -i -c -e "$pattern" "${doc_globs[@]}" "$docs_root" 2>/dev/null | sort -t: -k2 -nr | head -n "$max"
  echo
  echo "### Doc lines (first $max)"
  rg -i -n --no-heading -e "$pattern" "${doc_globs[@]}" "$docs_root" 2>/dev/null | cut -c1-260 | head -n "$max"
fi
echo

# Bridge: code-shaped identifiers (camelCase/PascalCase/snake/dotted) in backticks on doc lines
# that mention the concept, ranked by frequency. Plain words and HTTP verbs are dropped.
bridge=$( { [[ -d "$docs_root" ]] && rg -i --no-filename --no-line-number -e "$pattern" "${doc_globs[@]}" "$docs_root" 2>/dev/null; } \
  | rg -o '`[A-Za-z_\$][A-Za-z0-9_.\$]{2,60}`' 2>/dev/null | tr -d '`' \
  | rg -e '^[a-z_$][a-zA-Z0-9]*[A-Z]' -e '^[A-Z][a-z0-9]+[A-Z]' -e '^[a-z]+_[a-z_]+$' -e '^[A-Za-z]+\.[A-Za-z]' \
  | sort | uniq -c | sort -nr | awk '{print $2}' | head -n "${BRIDGE_MAX:-8}")
[[ -n "$bridge" ]] && { echo "### Code identifiers the docs pair with it (most frequent first)"; echo "$bridge" | tr '\n' ' '; echo; echo; }

[[ -d "$code_root" ]] || exit 0
esc() { python3 -c 'import re,sys; print(re.escape(sys.argv[1]))' "$1"; }

echo "### Where each identifier is defined or declared (main code first)"
found=0
while IFS= read -r id; do
  [[ -z "$id" ]] && continue
  e=$(esc "$id")
  hits=$(rg -n --no-heading \
      -e "(class|record|interface|enum|type|function|def|const)\s+$e\b" \
      -e "static final \S+ \w+\s*=\s*\"$e\"" -e "^\s*$e\s*[:=(]" \
      "${code_globs[@]}" "$code_root" 2>/dev/null | head -n 4)
  [[ -z "$hits" ]] && hits=$(rg -n --no-heading -F "\"$id\"" "${code_globs[@]}" "$code_root" 2>/dev/null | head -n 3)
  [[ -z "$hits" ]] && continue
  found=1; echo "#### $id"; echo "$hits" | cut -c1-240
done < <({ variants "$term"; for a in "${aliases[@]:-}"; do [[ -n "$a" ]] && variants "$a"; done; echo "$bridge"; } | awk 'NF && !seen[$0]++')
[[ $found == 0 ]] && echo "(none: try -a <codeName>, or INCLUDE_TESTS=1)"
echo

# Comments naming it. Code often uses a synonym ("attempt budget"), so fall back to the head noun.
echo "### Javadoc/comments naming it"
c=$(rg -i -n --no-heading -e "^\s*(\*|//|#).*($pattern)" "${code_globs[@]}" "$code_root" 2>/dev/null | head -n "$max")
if [[ -z "$c" ]]; then
  head_noun=$(echo "$term" | awk '{print $NF}')
  if [[ "$head_noun" != "$term" ]]; then
    echo "(phrase not found; head noun \"$head_noun\")"
    c=$(rg -i -n --no-heading -e "^\s*(\*|//|#).*\b$head_noun\b" "${code_globs[@]}" "$code_root" 2>/dev/null | head -n "$max")
  fi
fi
echo "${c:-(none)}" | cut -c1-240
