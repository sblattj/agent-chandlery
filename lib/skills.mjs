// List the bundled skills and install them into an agent client's skills directory.
import { readdirSync, readFileSync, existsSync, mkdirSync, cpSync, rmSync, symlinkSync, lstatSync, writeFileSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { homedir } from "node:os";
import { fileURLToPath } from "node:url";

export const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
export const SKILLS_DIR = join(ROOT, "skills");
const MARK = ".chandlery.json";

// Where each client looks for skills. Project scope is relative to the project root.
export const TARGETS = {
  claude: { user: "~/.claude/skills", project: ".claude/skills" },
  kiro: { user: "~/.kiro/skills", project: ".kiro/skills" },
  codex: { user: "~/.codex/skills", project: ".agents/skills" },
};

export function frontmatter(text) {
  const m = /^---\n([\s\S]*?)\n---/.exec(text);
  if (!m) return {};
  const out = {};
  for (const line of m[1].split("\n")) {
    const kv = /^([A-Za-z_][\w-]*):\s*(.*)$/.exec(line);
    if (!kv) continue;
    let v = kv[2].trim();
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) v = v.slice(1, -1);
    out[kv[1]] = v;
  }
  return out;
}

export function list(dir = SKILLS_DIR) {
  if (!existsSync(dir)) return [];
  return readdirSync(dir, { withFileTypes: true })
    .filter((d) => d.isDirectory() && existsSync(join(dir, d.name, "SKILL.md")))
    .map((d) => ({ name: d.name, dir: join(dir, d.name), ...frontmatter(readFileSync(join(dir, d.name, "SKILL.md"), "utf8")) }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

const expand = (p, home) => (p.startsWith("~/") ? join(home, p.slice(2)) : p);

export function targetDir(client, scope, { project = process.cwd(), home = homedir() } = {}) {
  const t = TARGETS[client];
  if (!t) throw new Error(`unknown client ${client} (one of ${Object.keys(TARGETS).join(", ")})`);
  return scope === "user" ? expand(t.user, home) : resolve(project, t[scope === "project" ? "project" : scope]);
}

// Old skill names that still work for --only / --exclude.
export const ALIASES = {
  "goal-state": "goal-file-autonomous-run-until-evidence",
  "explain-concept": "explain-code-concept-from-source-with-snippets-and-handdrawn-svg",
  "sketch": "building-a-local-html-visual-explainer",
  "work-overview": "summarizing-what-someone-shipped-from-git-log",
  "forge-skill": "forge-skill-from-session-friction",
  "big-tool-result": "reading-overflowed-tool-output",
  "landing-stacked-prs": "landing-stacked-github-prs",
  "pr-rereview-after-reply": "rereviewing-a-github-pr-after-reply",
  "cbm-index": "indexing-a-repo-into-codebase-memory",
  "codebase-memory": "querying-the-codebase-memory-graph",
  "cdp-route-snapshots": "diffing-web-app-aria-snapshots-a-vs-b",
  "evidence-dump": "snapshotting-shipped-work-since-a-date",
  "kiro-context-probe": "measuring-what-a-kiro-agent-loads-into-context",
  "narrated-ab-video": "recording-a-narrated-ab-proof-video",
  "narrated-screenshot": "making-a-narrated-ab-screenshot",
  "peer-relay": "relaying-a-go-ahead-to-another-claude-session",
  "pr-ab-evidence": "proving-a-bugfix-pr-red-to-green",
  "pr-activity-since-push": "checking-my-github-prs-for-activity-since-push",
  "pr-approval-gate": "checking-what-blocks-my-github-prs-from-merging",
  "pr-logic-trail": "walking-a-pr-logic-diff-in-request-order",
  "real-start-tokens": "measuring-claude-session-start-tokens",
  "sketch-local-html-visual-explainer": "building-a-local-html-visual-explainer",
  "skill-diet-audit": "auditing-skill-context-cost-from-session-logs",
  "skill-hint-hook": "building-a-prompt-to-skill-hint-hook",
  "skill-trigger-ab": "ab-testing-whether-skills-still-trigger",
  "swarm": "fanning-out-a-verified-read-only-swarm",
  "swarm-prompt": "writing-an-orchestrator-fan-out-prompt",
  "swarm-unit-pack": "fitting-a-50-plus-task-fan-out-under-workflow-limits",
  "watch-claude-session": "watching-another-claude-session-live",
  "what-the-other-agent-posted-on-github": "checking-what-another-agent-posted-on-github",
  "windows-vm-repro": "reproducing-a-windows-bug-in-a-fusion-vm-from-a-mac",
  "xx": "fanning-out-parallel-writers-with-verified-changes",
  "work-overview-from-git-log": "summarizing-what-someone-shipped-from-git-log",
};
const canon = (n) => ALIASES[n] || n;

// Copies (or links) skills. An existing dir is replaced only if chandlery put it there, or with force.
export function install({ clients = ["claude"], scope = "project", only: onlyIn, exclude: excludeIn = [], link = false, force = false, dryRun = false, project, home, version = "dev" } = {}) {
  const only = onlyIn?.map(canon);
  const exclude = excludeIn.map(canon);
  let skills = list();
  if (only?.length) {
    const missing = only.filter((n) => !skills.some((s) => s.name === n));
    if (missing.length) throw new Error(`no such skill: ${missing.join(", ")}`);
    skills = skills.filter((s) => only.includes(s.name));
  }
  skills = skills.filter((s) => !exclude.includes(s.name));
  const report = [];
  for (const client of clients) {
    const base = targetDir(client, scope, { project, home });
    for (const s of skills) {
      const dst = join(base, s.name);
      let action = "install";
      let exists = false;
      try { lstatSync(dst); exists = true; } catch {}
      if (exists) {
        const ours = existsSync(join(dst, MARK)) || (() => { try { return lstatSync(dst).isSymbolicLink(); } catch { return false; } })();
        if (!ours && !force) { report.push({ client, skill: s.name, dst, action: "skip (not ours; --force to replace)" }); continue; }
        action = "replace";
      }
      report.push({ client, skill: s.name, dst, action: link ? `${action} (link)` : action });
      if (dryRun) continue;
      mkdirSync(base, { recursive: true });
      if (exists) rmSync(dst, { recursive: true, force: true });
      if (link) symlinkSync(s.dir, dst);
      else {
        cpSync(s.dir, dst, { recursive: true });
        writeFileSync(join(dst, MARK), JSON.stringify({ source: "agent-chandlery", version }, null, 2) + "\n");
      }
    }
  }
  return report;
}
