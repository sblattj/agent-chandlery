#!/usr/bin/env bash
# save-prompt.sh <slug> : reads prompt text on stdin, writes it to
# ${PROMPTS_DIR:-${XDG_DATA_HOME:-~/.local/share}/swarm-prompts}/<slug>.prompt.md and prints the path.
# Slug is sanitized (lowercase, non [a-z0-9_-] dropped). Refuses an empty body.
set -euo pipefail
raw="${1:?usage: save-prompt.sh <slug>   (prompt text on stdin; PROMPTS_DIR overrides the output dir)}"
slug="$(printf '%s' "$raw" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-_' | sed 's/^-*//; s/-*$//')"
[ -n "$slug" ] || { echo "error: slug empty after sanitize" >&2; exit 2; }
dir="${PROMPTS_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/swarm-prompts}"
mkdir -p "$dir"
out="$dir/${slug}.prompt.md"
tmp="$(mktemp)"; cat > "$tmp"
[ -s "$tmp" ] || { rm -f "$tmp"; echo "error: empty prompt body on stdin" >&2; exit 3; }
mv "$tmp" "$out"
printf 'saved: %s (%s lines, %s bytes)\n' "$out" "$(wc -l < "$out" | tr -d ' ')" "$(wc -c < "$out" | tr -d ' ')"
