// Render title/evidence cards and corner banners to PNG with the browser as compositor.
// Usage: bun cards.ts <cards.json> <outDir>
// cards.json: { "size": [1280,800], "cards": { "title": "<h1>..</h1>", ... }, "banners": { "A": ["#b91c1c","A · base"], ... } }
// Card HTML can use classes: k (amber), g (green), r (red), tag a / tag b (A/B pills), small, pre.
import { chromium } from 'playwright'
import fs from 'fs'
import path from 'path'
const [cfgPath, out] = process.argv.slice(2)
const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8')); fs.mkdirSync(out, { recursive: true })
const [w, h] = cfg.size ?? [1280, 800]
const css = `body{margin:0;width:${w}px;height:${h}px;background:#0f172a;color:#e2e8f0;font-family:-apple-system,Helvetica,sans-serif;display:flex;flex-direction:column;justify-content:center;padding:0 80px;box-sizing:border-box}
h1{font-size:46px;margin:0 0 18px;color:#fff}h2{font-size:30px;margin:0 0 22px;color:#93c5fd}p,li{font-size:24px;line-height:1.45}
.k{color:#fbbf24}.g{color:#4ade80}.r{color:#f87171}pre{background:#020617;border:1px solid #334155;border-radius:10px;padding:16px 20px;font-size:17px;line-height:1.5;white-space:pre-wrap;color:#cbd5e1;margin:6px 0 14px}
.tag{display:inline-block;font-size:15px;padding:3px 10px;border-radius:6px;margin-right:8px;font-weight:600}.a{background:#7f1d1d;color:#fecaca}.b{background:#14532d;color:#bbf7d0}small{font-size:18px;color:#94a3b8}${cfg.css ?? ''}`
const exeDir = path.join(process.env.HOME!, 'Library/Caches/ms-playwright')
const exe = process.env.CHROMIUM_EXE ?? fs.readdirSync(exeDir).filter(d => /^chromium-\d+$/.test(d)).sort().reverse()
  .map(d => path.join(exeDir, d, 'chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing')).find(f => fs.existsSync(f))
const b = await chromium.launch({ executablePath: exe })
const p = await b.newPage({ viewport: { width: w, height: h } })
for (const [k, html] of Object.entries<string>(cfg.cards ?? {})) { await p.setContent(`<style>${css}</style>${html}`); await p.screenshot({ path: `${out}/${k}.png` }) }
const q = await b.newPage({ viewport: { width: w, height: 60 } })
for (const [k, [color, txt]] of Object.entries<[string, string]>(cfg.banners ?? {})) {
  await q.setContent(`<style>body{margin:0;background:transparent;font-family:-apple-system,Helvetica,sans-serif}div{position:absolute;right:16px;top:10px;padding:8px 16px;border-radius:8px;font-size:22px;font-weight:700;color:#fff;background:${color}}</style><div>${txt}</div>`)
  await q.screenshot({ path: `${out}/banner-${k}.png`, omitBackground: true })
}
await b.close()
console.log(fs.readdirSync(out).filter(f => f.endsWith('.png')).join(' '))
