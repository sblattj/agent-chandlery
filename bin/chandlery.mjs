#!/usr/bin/env node
// chandlery: list and install agent skills, and run a goal-state loop.
import { readFileSync, existsSync, writeFileSync, mkdirSync } from "node:fs";
import { join, dirname, resolve } from "node:path";
import * as goal from "../lib/goal.mjs";
import * as skills from "../lib/skills.mjs";

const pkg = JSON.parse(readFileSync(join(skills.ROOT, "package.json"), "utf8"));

const HELP = `chandlery ${pkg.version}

Skills
  chandlery list [--json]
  chandlery install [--client claude|kiro|codex ...] [--scope project|user] [--project DIR]
                    [--only a,b] [--exclude a,b] [--link] [--force] [--dry-run]

Goal state (file: .chandlery/goal.json, or --file / CHANDLERY_GOAL_FILE)
  chandlery goal set "<objective>" [--brief-file F] [--success "..."]... [--constraint "..."]...
                    [--mode ordered] [--max-minutes N] [--max-turns N] [--max-tokens N] [--stall-turns N]
  chandlery goal status [--json]
  chandlery goal validate [FILE]
  chandlery goal plan add <id> "<title>"
  chandlery goal act <id> <pending|in_progress|done|blocked> [--claim ..] [--evidence ..] [--verdict pass|fail] [--reason ..]
  chandlery goal complete --summary "..." --evidence "..."
  chandlery goal block "<what only the human can give>"
  chandlery goal pause | resume | clear
  chandlery goal turn [--tokens N]       record one finished turn, print continue / wrapup / stop
  chandlery goal prompt                  print the continuation prompt
  chandlery goal hook claude             Claude Code Stop hook (reads hook JSON on stdin)
  chandlery goal hook install [--scope project|user] [--command CMD]
`;

// --flag value / --flag=value; repeatable flags collect into arrays.
function parse(argv, repeat = []) {
  const pos = [], opt = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith("--")) { pos.push(a); continue; }
    let [k, v] = a.slice(2).split(/=(.*)/s);
    const bool = ["json", "link", "force", "dry-run"].includes(k);
    if (v === undefined && !bool) {
      v = argv[++i];
      if (v === undefined) throw new Error(`--${k} needs a value`);
    }
    if (bool && v === undefined) v = true;
    if (repeat.includes(k)) (opt[k] ||= []).push(v);
    else opt[k] = v;
  }
  return { pos, opt };
}

const int = (v, name) => {
  if (v === undefined) return undefined;
  const n = Number(v);
  if (!Number.isInteger(n) || n < 0) throw new Error(`--${name} must be an integer >= 0 (0 = unlimited)`);
  return n;
};
const csv = (v) => (v ? String(v).split(",").map((s) => s.trim()).filter(Boolean) : undefined);

function need(file) {
  const g = goal.load(file);
  if (!g) throw new Error(`no goal at ${goal.goalPath(file)}; run: chandlery goal set "<objective>"`);
  return g;
}

async function readStdin() {
  if (process.stdin.isTTY) return "";
  let s = "";
  for await (const c of process.stdin) s += c;
  return s;
}

function hookInstall(opt) {
  const scope = opt.scope || "project";
  const file = scope === "user" ? join(process.env.HOME, ".claude", "settings.json") : resolve(opt.project || ".", ".claude", "settings.json");
  const command = opt.command || "chandlery goal hook claude";
  const s = existsSync(file) ? JSON.parse(readFileSync(file, "utf8")) : {};
  s.hooks ||= {};
  s.hooks.Stop ||= [];
  const has = s.hooks.Stop.some((m) => (m.hooks || []).some((h) => h.command === command));
  if (!has) s.hooks.Stop.push({ hooks: [{ type: "command", command }] });
  if (!opt["dry-run"]) { mkdirSync(dirname(file), { recursive: true }); writeFileSync(file, JSON.stringify(s, null, 2) + "\n"); }
  return `${has ? "already present" : opt["dry-run"] ? "would add" : "added"}: Stop hook "${command}" in ${file}`;
}

async function goalCmd(argv) {
  const { pos, opt } = parse(argv, ["success", "constraint"]);
  const [sub = "status", ...rest] = pos;
  const file = opt.file;
  const out = (s) => process.stdout.write(s + "\n");
  switch (sub) {
    case "set": {
      const brief = opt["brief-file"] ? readFileSync(opt["brief-file"], "utf8") : undefined;
      const g = goal.create({
        objective: rest.join(" ") || undefined, brief, success: opt.success, constraints: opt.constraint, mode: opt.mode || "normal",
        budget: Object.fromEntries(Object.entries({ maxMinutes: int(opt["max-minutes"], "max-minutes"), maxTurns: int(opt["max-turns"], "max-turns"), maxTokens: int(opt["max-tokens"], "max-tokens"), stallTurns: int(opt["stall-turns"], "stall-turns") }).filter(([, v]) => v !== undefined)),
      });
      const problems = goal.validate(g);
      if (problems.length) throw new Error(problems.join("\n"));
      goal.save(g, file, { event: "set", note: g.objective });
      return out(goal.status(g));
    }
    case "status": {
      const g = goal.load(file);
      if (!g) return out(opt.json ? "null" : "No goal set.");
      return out(opt.json ? JSON.stringify(g, null, 2) : goal.status(g));
    }
    case "validate": {
      const f = rest[0] || file;
      const g = goal.load(f);
      if (!g) throw new Error(`no goal at ${goal.goalPath(f)}`);
      const problems = goal.validate(g);
      if (problems.length) { out(problems.map((p) => `- ${p}`).join("\n")); process.exitCode = 1; return; }
      return out("valid");
    }
    case "plan": {
      if (rest[0] !== "add") throw new Error('usage: chandlery goal plan add <id> "<title>"');
      const g = need(file);
      const ev = goal.planAdd(g, rest[1], rest.slice(2).join(" "));
      goal.save(g, file, ev);
      return out(goal.status(g));
    }
    case "act": {
      const g = need(file);
      const ev = goal.act(g, rest[0], rest[1], { claim: opt.claim, evidence: opt.evidence, verdict: opt.verdict, reason: opt.reason });
      goal.save(g, file, ev);
      return out(goal.status(g));
    }
    case "complete": {
      const g = need(file);
      goal.save(g, file, goal.complete(g, { summary: opt.summary, evidence: opt.evidence }));
      return out(goal.status(g));
    }
    case "block": {
      const g = need(file);
      goal.save(g, file, goal.block(g, rest.join(" ")));
      return out(goal.status(g));
    }
    case "pause": case "halt": {
      const g = need(file);
      goal.save(g, file, goal.pause(g, "paused by user"));
      return out(goal.status(g));
    }
    case "resume": {
      const g = need(file);
      goal.save(g, file, goal.resume(g));
      return out(goal.status(g));
    }
    case "clear": {
      const g = goal.load(file);
      if (!g) return out("No goal set.");
      g.state = "paused"; g.stopReason = "cleared";
      goal.save(g, file, { event: "clear" });
      const { renameSync } = await import("node:fs");
      const f = goal.goalPath(file);
      renameSync(f, `${f}.cleared-${Date.now()}`);
      return out("Cleared.");
    }
    case "turn": {
      const g = need(file);
      const r = goal.turn(g, { tokens: int(opt.tokens, "tokens") || 0 });
      goal.save(g, file, { event: "turn", note: r.decision + (r.why ? `: ${r.why}` : "") });
      out(r.decision + (r.why ? `: ${r.why}` : ""));
      if (r.decision !== "stop") out("\n" + goal.continuationPrompt(g, r.decision));
      return;
    }
    case "prompt": return out(goal.continuationPrompt(need(file)));
    case "hook": {
      if (rest[0] === "install") return out(hookInstall(opt));
      if (rest[0] !== "claude") throw new Error("usage: chandlery goal hook claude | install");
      // Claude Code Stop hook: block the stop with the continuation prompt while the goal is active.
      let input = {};
      try { input = JSON.parse((await readStdin()) || "{}"); } catch {}
      const f = file || (input.cwd ? join(input.cwd, ".chandlery", "goal.json") : undefined);
      const g = goal.load(f);
      if (!g || g.state !== "active") return;
      const r = goal.turn(g);
      goal.save(g, f, { event: "turn", note: r.decision + (r.why ? `: ${r.why}` : "") });
      if (r.decision === "stop") return;
      return out(JSON.stringify({ decision: "block", reason: goal.continuationPrompt(g, r.decision) }));
    }
    default: throw new Error(`unknown goal command ${sub}\n\n${HELP}`);
  }
}

async function main(argv) {
  const [cmd, ...rest] = argv;
  if (!cmd || cmd === "help" || cmd === "--help" || cmd === "-h") return process.stdout.write(HELP);
  if (cmd === "--version" || cmd === "-v") return process.stdout.write(pkg.version + "\n");
  if (cmd === "goal") return goalCmd(rest);
  if (cmd === "list") {
    const { opt } = parse(rest);
    const all = skills.list();
    if (opt.json) return process.stdout.write(JSON.stringify(all.map(({ name, description }) => ({ name, description })), null, 2) + "\n");
    const w = Math.max(...all.map((s) => s.name.length), 4);
    for (const s of all) process.stdout.write(`${s.name.padEnd(w)}  ${(s.description || "").slice(0, 100)}\n`);
    return;
  }
  if (cmd === "install") {
    const { opt } = parse(rest, ["client"]);
    const report = skills.install({
      clients: opt.client || ["claude"], scope: opt.scope || "project", project: opt.project,
      only: csv(opt.only), exclude: csv(opt.exclude) || [], link: !!opt.link, force: !!opt.force, dryRun: !!opt["dry-run"], version: pkg.version,
    });
    for (const r of report) process.stdout.write(`${r.action.padEnd(12)} ${r.client.padEnd(6)} ${r.skill} -> ${r.dst}\n`);
    return;
  }
  throw new Error(`unknown command ${cmd}\n\n${HELP}`);
}

main(process.argv.slice(2)).catch((e) => { process.stderr.write(`chandlery: ${e.message}\n`); process.exit(1); });
