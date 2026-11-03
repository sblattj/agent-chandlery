#!/usr/bin/env bash
# Check the narrated-video toolchain: playwright module, a cached chromium, playwright's ffmpeg, system ffmpeg, say.
set -u
WORK="${1:-/tmp/vid}"
mkdir -p "$WORK"; cd "$WORK" || exit 1
[ -f package.json ] || bun init -y >/dev/null 2>&1
[ -d node_modules/playwright ] || bun add playwright@1 >/dev/null 2>&1
C=~/Library/Caches/ms-playwright
ls -d $C/chromium-[0-9]*/chrome-mac-arm64 >/dev/null 2>&1 && echo "ok   chromium: $(ls -d $C/chromium-[0-9]* | tail -1)" || echo "MISS chromium: bunx playwright install chromium"
need=$(jq -r '.browsers[]|select(.name=="ffmpeg").revision' node_modules/playwright-core/browsers.json 2>/dev/null)
[ -x "$C/ffmpeg-$need/ffmpeg-mac" ] && echo "ok   playwright ffmpeg-$need" || { echo "fix  playwright ffmpeg-$need missing: installing"; bunx playwright install ffmpeg >/dev/null 2>&1 && echo "ok   installed ffmpeg-$need"; }
command -v ffmpeg >/dev/null && echo "ok   ffmpeg $(ffmpeg -version | head -1 | cut -d' ' -f3)" || echo "MISS ffmpeg: brew install ffmpeg"
ffmpeg -hide_banner -filters 2>/dev/null | grep -q ' drawtext ' && echo "ok   drawtext" || echo "note no drawtext in this ffmpeg: banners are PNG overlays (cards.ts)"
say -v '?' | grep -q '^Samantha' && echo "ok   say voice Samantha" || echo "note Samantha voice missing: pass --voice"
echo "work dir: $WORK (copy record.ts/cards.ts here or run them by path)"
