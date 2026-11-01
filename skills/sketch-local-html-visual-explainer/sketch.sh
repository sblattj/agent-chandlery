#!/usr/bin/env bash
# sketch.sh: path / lint / screenshot / open for local HTML visual explainers.
#   sketch.sh path <slug>            print where to save (repo tmp/ if gitignored, else ~/sketches)
#   sketch.sh check <file.html>      lint + headless screenshot (PNG path printed) + open
#   env: SKETCH_NO_OPEN=1 skip open, SKETCH_NO_SHOT=1 skip screenshot, SKETCH_WIDTH (1280), SKETCH_HEIGHT (4200),
#        SKETCH_CHROME=<browser binary> (default: Google Chrome on macOS), SKETCH_BANNED_RE=<regex> optional style lint
set -euo pipefail
cmd="${1:-}"; arg="${2:-}"
[[ -z "$cmd" || -z "$arg" ]] && { sed -n '2,6p' "$0"; exit 2; }

case "$cmd" in
path)
  root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n "$root" ]] && git -C "$root" check-ignore -q "tmp/$arg.html"; then
    mkdir -p "$root/tmp"; echo "$root/tmp/$arg.html"
  else
    mkdir -p "$HOME/sketches"; echo "$HOME/sketches/$arg.html"
  fi ;;
check)
  f="$arg"; [[ -f "$f" ]] || { echo "no such file: $f"; exit 1; }
  fail=0
  warn() { echo "WARN: $*"; fail=1; }
  # optional house-style check: SKETCH_BANNED_RE='regex' flags lines matching it (e.g. words or characters you avoid)
  if [[ -n "${SKETCH_BANNED_RE:-}" ]]; then n=$(grep -cE "$SKETCH_BANNED_RE" "$f" || true); [[ "$n" == 0 ]] || warn "$n line(s) match SKETCH_BANNED_RE"; fi
  grep -q '<title>' "$f" || warn "missing <title>"
  grep -q 'prefers-color-scheme: dark' "$f" || warn "no dark palette"
  # Navigation links may cite sources; resources loaded by the page must stay local.
  # Static attributes only; verify browser requests for CSS and dynamic resources.
  if ! python3 - "$f" <<'PY'
import re
import sys
from html.parser import HTMLParser

remote = re.compile(r'^(?:https?:)?//', re.I)

class Assets(HTMLParser):
    external = False

    def handle_starttag(self, tag, attrs):
        for name, value in attrs:
            if not value:
                continue
            if name in ('href', 'xlink:href') and tag in ('a', 'area'):
                continue
            if name in ('src', 'href', 'xlink:href', 'poster') or (tag == 'object' and name == 'data'):
                self.external |= bool(remote.match(value.strip()))
            elif name == 'srcset':
                self.external |= any(remote.match(item.strip().split()[0])
                                     for item in value.split(',') if item.strip())

parser = Assets()
with open(sys.argv[1], encoding='utf-8') as source:
    parser.feed(source.read())
sys.exit(1 if parser.external else 0)
PY
  then
    warn "external asset URL found (keep it self-contained)"
  fi
  grep -q '<svg' "$f" && ! grep -q 'min-width' "$f" && warn "svg without min-width scroll guard"
  # long single-line SVG text overflows its box (~6.5px/char at 12-13px)
  long=$(grep -oE '<text[^>]*>[^<]{56,}</text>' "$f" | sed -E 's/<[^>]+>//g' || true)
  [[ -n "$long" ]] && warn "SVG text >55 chars, may overflow its box:"$'\n'"$long"
  if git -C "$(dirname "$f")" rev-parse 2>/dev/null && ! git -C "$(dirname "$f")" check-ignore -q "$f"; then
    warn "file is inside a git repo and NOT ignored"
  fi
  [[ $fail == 0 ]] && echo "lint: clean"
  if [[ -z "${SKETCH_NO_SHOT:-}" ]]; then
    chrome="${SKETCH_CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
    png="${f%.html}.png"
    if [[ -x "$chrome" ]]; then
      for scheme in light dark; do
        out="${png%.png}-$scheme.png"
        # headless follows the macOS appearance, so force BOTH schemes explicitly (0=dark, 1=light)
        flag="--blink-settings=preferredColorScheme=1"; [[ $scheme == dark ]] && flag="--force-dark-mode --blink-settings=preferredColorScheme=0"
        # shellcheck disable=SC2086
        perl -e 'alarm shift; exec @ARGV' 60 "$chrome" --headless=new --disable-gpu --hide-scrollbars --virtual-time-budget=4000 $flag \
          --window-size="${SKETCH_WIDTH:-1280},${SKETCH_HEIGHT:-4200}" --screenshot="$out" "file://$(cd "$(dirname "$f")" && pwd)/$(basename "$f")" >/dev/null 2>&1 \
          && echo "shot: $out" || echo "shot failed ($scheme)"
      done
    else echo "shot: skipped (no Chromium-family browser at $chrome; set SKETCH_CHROME)"; fi
  fi
  [[ -z "${SKETCH_NO_OPEN:-}" ]] && open "$f"
  exit $fail ;;
*) sed -n '2,6p' "$0"; exit 2 ;;
esac
