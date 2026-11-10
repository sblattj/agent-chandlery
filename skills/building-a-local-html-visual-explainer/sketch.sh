#!/usr/bin/env bash
# sketch.sh: path / lint / screenshot / open for local HTML visual explainers.
#   sketch.sh path <slug> [topic]    print where to save: $SKETCH_DIR/<topic>/ if set, else repo tmp/ if gitignored, else ~/sketches/
#   sketch.sh check <file.html>      lint + headless screenshot (PNG path printed) + open
#   env: SKETCH_NO_OPEN=1 skip open, SKETCH_NO_SHOT=1 skip screenshot, SKETCH_WIDTH (1280), SKETCH_HEIGHT (4200),
#        SKETCH_CHROME=<browser binary> (default: the first of Chromium, Vivaldi, Brave, Edge; never Google Chrome unless set here),
#        SKETCH_DIR=<dir> (pages go to <dir>/<topic>/), SKETCH_BANNED_RE=<regex> optional style lint
set -euo pipefail
cmd="${1:-}"; arg="${2:-}"
[[ -z "$cmd" || -z "$arg" ]] && { sed -n '2,7p' "$0"; exit 2; }

case "$cmd" in
path)
  topic="${3:-}"
  if [[ -n "${SKETCH_DIR:-}" ]]; then
    d="${SKETCH_DIR/#\~/$HOME}${topic:+/$topic}"; mkdir -p "$d"; echo "$d/$arg.html"; exit 0
  fi
  root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n "$root" ]] && git -C "$root" check-ignore -q "tmp/$arg.html"; then
    mkdir -p "$root/tmp"; echo "$root/tmp/$arg.html"
  else
    d="$HOME/sketches${topic:+/$topic}"; mkdir -p "$d"; echo "$d/$arg.html"
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
    chrome="${SKETCH_CHROME:-}"
    if [[ -z "$chrome" ]]; then
      for c in "/Applications/Chromium.app/Contents/MacOS/Chromium" "/Applications/Vivaldi.app/Contents/MacOS/Vivaldi" \
               "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" \
               "$(command -v chromium 2>/dev/null || true)" "$(command -v chromium-browser 2>/dev/null || true)"; do
        [[ -n "$c" && -x "$c" ]] && { chrome="$c"; break; }
      done
    fi
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
    else echo "shot: skipped (no Chromium-family browser found; set SKETCH_CHROME, or screenshot each figure in your CDP browser)"; fi
  fi
  [[ -z "${SKETCH_NO_OPEN:-}" ]] && open "$f"
  exit $fail ;;
*) sed -n '2,7p' "$0"; exit 2 ;;
esac
