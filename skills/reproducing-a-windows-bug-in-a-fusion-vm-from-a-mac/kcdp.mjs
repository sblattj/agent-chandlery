#!/usr/bin/env node
// CDP client for Kiro IDE (VS Code fork) reached over the network. Usage:
//   kcdp.mjs <host:port> targets            list page/webview targets
//   kcdp.mjs <host:port> text [chat|main]   visible text, shadow roots included (default: both)
//   kcdp.mjs <host:port> click "<label>"    click the first button/link whose text matches, in main then chat
//   kcdp.mjs <host:port> eval '<js>'        run JS in the Kiro agent chat webview (frames that have content)
//   kcdp.mjs <host:port> evalmain '<js>'    run JS in the workbench window
//   kcdp.mjs <host:port> send '<prompt>'     type into the Kiro chat input (ProseMirror) with real CDP key input, press Enter
//   kcdp.mjs <host:port> shot <file.png>    screenshot the workbench window
const [hostport, cmd = 'targets', arg] = process.argv.slice(2);
if (!hostport) { console.error('usage: kcdp.mjs <host:port> <cmd> [arg]'); process.exit(2); }
const targets = await (await fetch(`http://${hostport}/json/list`)).json();
const main = targets.find(t => t.type === 'page' && t.url.startsWith('vscode-file://'));
const chat = targets.find(t => t.type === 'iframe' && t.url.includes('extensionId=kiro.kiroAgent'));
if (cmd === 'targets') { for (const t of targets) console.log(`${t.type}\t${t.title.slice(0, 40)}\t${(t.url.match(/extensionId=[^&]+/) || [t.url.slice(0, 60)])[0]}`); process.exit(0); }

async function session(target) {
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  let id = 0; const pending = new Map(); const contexts = [];
  ws.onmessage = (m) => { const d = JSON.parse(m.data);
    if (d.id && pending.has(d.id)) { pending.get(d.id)(d); pending.delete(d.id); }
    if (d.method === 'Runtime.executionContextCreated') contexts.push(d.params.context); };
  const send = (method, params = {}) => new Promise(r => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  await send('Runtime.enable'); await new Promise(r => setTimeout(r, 400));
  const evalIn = async (expr, ctxId) => { const r = await send('Runtime.evaluate', { expression: expr, contextId: ctxId, awaitPromise: true, returnByValue: true });
    return r.result?.exceptionDetails ? { error: r.result.exceptionDetails.exception?.description } : r.result?.result?.value; };
  // the chat webview nests its UI in an inner frame: only use default contexts that render text
  const live = async () => { const out = [];
    for (const c of contexts.filter(c => c.auxData?.isDefault)) if ((await evalIn('(document.body?.innerText||"").length', c.id)) > 0) out.push(c.id);
    return out.length ? out : [undefined]; };
  return { send, evalIn, live, close: () => ws.close() };
}
// deep helpers: Kiro renders some screens (e.g. sign-in) inside shadow roots, which innerText/querySelector skip
const DEEP = `const __all=(r=document,a=[])=>{for(const e of r.querySelectorAll('*')){a.push(e);if(e.shadowRoot)__all(e.shadowRoot,a)}return a};`;
const TEXT = `(()=>{${DEEP}const t=[document.body?.innerText||''];for(const e of __all())if(e.shadowRoot)t.push([...e.shadowRoot.children].filter(c=>!/^(STYLE|SCRIPT|LINK)$/.test(c.tagName)).map(c=>c.innerText||'').join(' ').trim());return t.filter(Boolean).join('\\n---\\n')})()`;
const CLICK = (label) => `(()=>{${DEEP}const re=new RegExp('^\\\\s*'+${JSON.stringify(label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'))}+'\\\\s*$','i');const el=__all().find(e=>/^(BUTTON|A)$/.test(e.tagName)&&re.test(e.textContent));if(!el)return 'not found';el.click();return 'clicked '+el.tagName})()`;

const which = { chat: [chat], main: [main] }[arg] || [main, chat];
if (cmd === 'shot') { const s = await session(main); const r = await s.send('Page.captureScreenshot', { format: 'png' });
  (await import('fs')).writeFileSync(arg, Buffer.from(r.result.data, 'base64')); console.log('saved', arg); s.close(); }
else if (cmd === 'text' || cmd === 'click') {
  for (const t of (cmd === 'click' ? [main, chat] : which).filter(Boolean)) { const s = await session(t);
    for (const c of await s.live()) { const v = await s.evalIn(cmd === 'text' ? TEXT : CLICK(arg), c);
      console.log(`[${t === main ? 'main' : 'chat'}] ${typeof v === 'string' ? v : JSON.stringify(v)}`);
      if (cmd === 'click' && typeof v === 'string' && v.startsWith('clicked')) { s.close(); process.exit(0); } }
    s.close(); }
  if (cmd === 'click') process.exit(1);
} else if (cmd === 'send') {
  // synthetic DOM events don't drive ProseMirror reliably; focus it, then use the Input domain (trusted events)
  const s = await session(chat); let ok = false;
  for (const c of await s.live()) { const r = await s.evalIn(`(()=>{const e=document.querySelector('.chat-input-content');if(!e)return false;e.focus();return true})()`, c); if (r === true) { ok = true; break; } }
  if (!ok) { console.error('chat input not found'); process.exit(1); }
  await s.send('Input.insertText', { text: arg });
  await new Promise(r => setTimeout(r, 300));
  for (const type of ['keyDown', 'keyUp']) await s.send('Input.dispatchKeyEvent', { type, key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13, ...(type === 'keyDown' ? { text: '\r' } : {}) });
  console.log('sent'); s.close();
} else if (cmd === 'eval' || cmd === 'evalmain') {
  const t = cmd === 'eval' ? chat : main; if (!t) { console.error('target not found'); process.exit(2); }
  const s = await session(t);
  for (const c of cmd === 'eval' ? await s.live() : [undefined]) console.log(JSON.stringify(await s.evalIn(arg, c), null, 1));
  s.close();
} else { console.error('unknown cmd ' + cmd); process.exit(2); }
process.exit(0);
