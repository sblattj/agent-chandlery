// Record one browser run as a webm with timing marks, driven by a scenario JSON.
// Usage: bun record.ts <scenario.json> <outDir>
// Scenario: { "url": "...", "viewport": [1280,800], "localStorage": {k:v}, "steps": [ ... ] }
// Steps (run in order):
//   {"wait": ms}                         {"select": ["css", "value"]}
//   {"click": "Button name regex"}        {"clickIfPresent": "regex"}   (role=button, first match)
//   {"type": ["css", "text"]}             (types with a visible 18ms keystroke delay)
//   {"send": "Button name regex"}         clicks it and marks "sent"
//   {"waitStable": {"timeoutS": 240, "stableS": 4}}   waits until page text stops changing, marks "replied"
//   {"expand": "regex"}                   clicks every matching button, marks "expanded", scrolls down
//   {"fetchText": {"url": "...", "headers": {}, "save": "file.json"}}  saves an API response next to the video
//   {"waitText": {"text": "regex", "timeoutS": 120, "mark": "label"}}  waits until page text matches, marks label (or "timeout:label")
//   {"probeEnabled": {"role": "Button name regex" | "css": "...", "mark": "label", "waitMs": 0}}  marks "label:enabled" or "label:disabled" (no click); waitMs polls until enabled
//   {"reload": true}                      reloads the page, marks "reloaded"
//   Add "tryMs": N to type/send/click to give up after N ms and mark "skipped:<step>" instead of failing
// Turn text "{{fn:NAME}}" is replaced by the result of hooks[NAME](page) from an optional hooks.ts beside the scenario.
import { chromium } from 'playwright'
import fs from 'fs'
import path from 'path'

const [scenarioPath, outDir] = process.argv.slice(2)
if (!scenarioPath || !outDir) { console.error('usage: bun record.ts <scenario.json> <outDir>'); process.exit(2) }
const sc = JSON.parse(fs.readFileSync(scenarioPath, 'utf8'))
const hooksFile = path.join(path.dirname(path.resolve(scenarioPath)), 'hooks.ts')
const hooks: Record<string, (p: any, ctx: any) => Promise<string>> = fs.existsSync(hooksFile) ? (await import(hooksFile)).default : {}

// Playwright's pinned headless shell is often not downloaded; fall back to any cached full chromium.
function chromiumExe(): string | undefined {
  if (process.env.CHROMIUM_EXE) return process.env.CHROMIUM_EXE
  const cache = path.join(process.env.HOME!, 'Library/Caches/ms-playwright')
  if (!fs.existsSync(cache)) return undefined
  const dirs = fs.readdirSync(cache).filter(d => /^chromium-\d+$/.test(d)).sort().reverse()
  for (const d of dirs) {
    const mac = path.join(cache, d, 'chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing')
    if (fs.existsSync(mac)) return mac
  }
  return undefined
}

const [w, h] = sc.viewport ?? [1280, 800]
fs.rmSync(outDir, { recursive: true, force: true })
const browser = await chromium.launch({ executablePath: chromiumExe() })
const ctx = await browser.newContext({ viewport: { width: w, height: h }, recordVideo: { dir: outDir, size: { width: w, height: h } } })
if (sc.localStorage) await ctx.addInitScript((kv: Record<string, string>) => { for (const [k, v] of Object.entries(kv)) localStorage.setItem(k, v) }, sc.localStorage)
const p = await ctx.newPage()
const state: any = {}
p.on('response', async r => { try { if (sc.captureJsonFrom && new RegExp(sc.captureJsonFrom).test(r.url()) && r.request().method() === 'POST') state.lastJson = await r.json() } catch {} })
const t0 = Date.now(); const marks: { label: string; t: number }[] = []
const mark = (label: string) => marks.push({ label, t: +((Date.now() - t0) / 1000).toFixed(2) })
const btn = (re: string) => p.getByRole('button', { name: new RegExp(re) })
const fill = async (s: string) => { const m = s.match(/^\{\{fn:(\w+)\}\}$/); return m ? hooks[m[1]](p, state) : s }

await p.goto(sc.url)
const probes: { label: string; enabled: boolean; t: number }[] = []
for (const st of sc.steps) {
  if (st.tryMs) {
    const kind = Object.keys(st).find(k => k !== 'tryMs')!
    try {
      if (kind === 'type') { const box = p.locator(st.type[0]).last(); await box.click({ timeout: st.tryMs }); mark('typing'); await box.pressSequentially(await fill(st.type[1]), { delay: 18, timeout: st.tryMs }) }
      else if (kind === 'send') { await btn(st.send).first().click({ timeout: st.tryMs }); mark('sent') }
      else if (kind === 'click') await btn(st.click).first().click({ timeout: st.tryMs })
    } catch { mark(`skipped:${kind}`) }
    continue
  }
  if ('waitText' in st) {
    const { text, timeoutS = 120, mark: label = 'text' } = st.waitText
    const re = new RegExp(text); let hit = false
    for (let i = 0; i < timeoutS * 2 && !hit; i++) { hit = re.test(await p.locator('body').innerText()); if (!hit) await p.waitForTimeout(500) }
    mark(hit ? label : `timeout:${label}`)
  } else if ('probeEnabled' in st) {
    const el = (st.probeEnabled.role ? btn(st.probeEnabled.role) : p.locator(st.probeEnabled.css)).first()
    const until = Date.now() + (st.probeEnabled.waitMs ?? 0)
    let enabled = (await el.count()) ? await el.isEnabled() : false
    while (!enabled && Date.now() < until) { await p.waitForTimeout(100); enabled = (await el.count()) ? await el.isEnabled() : false }
    const label = `${st.probeEnabled.mark ?? 'probe'}:${enabled ? 'enabled' : 'disabled'}`
    mark(label); probes.push({ label, enabled, t: marks[marks.length - 1].t })
  } else if ('reload' in st) { await p.reload(); mark('reloaded') }
  else if ('wait' in st) await p.waitForTimeout(st.wait)
  else if ('select' in st) await p.locator(st.select[0]).first().selectOption(st.select[1])
  else if ('click' in st) await btn(st.click).first().click()
  else if ('clickIfPresent' in st) { const b = btn(st.clickIfPresent); if (await b.count()) await b.first().click() }
  else if ('type' in st) { const box = p.locator(st.type[0]).last(); await box.click(); mark('typing'); await box.pressSequentially(await fill(st.type[1]), { delay: 18 }) }
  else if ('send' in st) { await btn(st.send).first().click(); mark('sent') }
  else if ('waitStable' in st) {
    const { timeoutS = 240, stableS = 4 } = st.waitStable
    const before = await p.locator('body').innerText(); let last = '', stable = 0
    for (let i = 0; i < timeoutS && stable < stableS; i++) {
      await p.waitForTimeout(1000)
      const now = await p.locator('body').innerText()
      if (now !== before && now === last) stable++; else stable = 0
      last = now
    }
    mark('replied'); await p.waitForTimeout(2500)
  } else if ('expand' in st) {
    const b = btn(st.expand); const n = await b.count()
    for (let i = 0; i < n; i++) { await b.nth(i).click().catch(() => {}); await p.waitForTimeout(600) }
    mark('expanded'); await p.mouse.wheel(0, 4000); await p.waitForTimeout(3500)
  } else if ('fetchText' in st) {
    const url = await fill(st.fetchText.url)
    const r = await fetch(url, { headers: st.fetchText.headers ?? {} })
    fs.writeFileSync(path.join(outDir, st.fetchText.save), await r.text())
  }
}
await p.waitForTimeout(1500)
fs.writeFileSync(path.join(outDir, 'marks.json'), JSON.stringify({ marks, probes, body: await p.locator('body').innerText() }, null, 1))
await ctx.close(); await browser.close()
const vid = fs.readdirSync(outDir).find(f => f.endsWith('.webm'))
console.log(JSON.stringify({ video: path.join(outDir, vid!), marks }))
