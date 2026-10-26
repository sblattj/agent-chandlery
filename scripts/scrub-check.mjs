#!/usr/bin/env node
// Public-repo leak gate with generic patterns only: personal home paths, tracker ids, emails, tokens,
// em dashes. Org- or person-specific terms never belong here; keep those in a local, untracked list
// and pass it with SCRUB_EXTRA=<file> (one term or re:regex per line).
import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { join, relative } from "node:path";

const ROOT = process.argv[2] || process.cwd();
const SKIP = new Set([".git", "node_modules", ".chandlery"]);
const RULES = [
  ["home path", /\/(?:Users|home)\/(?!<|\$|you\b|me\b|name\b|runner\b|user\b|USER\b)[A-Za-z0-9._-]+/],
  ["tracker id", /\bAB#\d{4,}\b|\bPBI[-\s]?\d{3,}\b|\bwork[-\s]?item[-\s]?#?\d{3,}\b/i],
  ["email", /\b[A-Za-z0-9._%+-]+@(?!example\.(?:com|org)|users\.noreply\.github\.com|anthropic\.com)[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/],
  ["token", /\b(?:ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9-]{20,}|AKIA[0-9A-Z]{16}|xox[bp]-[A-Za-z0-9-]{10,})\b/],
  ["em dash", /—/],
];
if (process.env.SCRUB_EXTRA && existsSync(process.env.SCRUB_EXTRA)) {
  for (const l of readFileSync(process.env.SCRUB_EXTRA, "utf8").split("\n").map((s) => s.trim()).filter((s) => s && !s.startsWith("#"))) {
    RULES.push(["local term", l.startsWith("re:") ? new RegExp(l.slice(3), "i") : new RegExp(l.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "i")]);
  }
}
// SCRUB_ALLOW: comma-separated literals removed before matching (e.g. the repo owner's public handle).
const ALLOW = (process.env.SCRUB_ALLOW || "").split(",").map((s) => s.trim()).filter(Boolean);
const allow = (rel) => rel === "scripts/scrub-check.mjs" || rel.startsWith("test/fixtures/");
const files = [];
(function walk(d) {
  for (const n of readdirSync(d)) {
    if (SKIP.has(n)) continue;
    const p = join(d, n), st = statSync(p);
    if (st.isDirectory()) walk(p); else if (st.size < 2_000_000) files.push(p);
  }
})(ROOT);
let hits = 0;
for (const f of files) {
  const rel = relative(ROOT, f);
  if (allow(rel)) continue;
  const text = readFileSync(f, "utf8");
  if (text.includes("\u0000")) continue;
  text.split("\n").forEach((raw, i) => {
    const line = ALLOW.reduce((l, a) => l.split(a).join(""), raw);
    for (const [label, re] of RULES) {
      const m = re.exec(line);
      if (m) { hits++; console.log(`${rel}:${i + 1}: ${label}: ${m[0]}`); }
    }
  });
}
if (hits) { console.log(`\n${hits} hit(s). Generalize them before pushing.`); process.exit(1); }
console.log(`scrub: ${files.length} files clean`);
