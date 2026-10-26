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

// Copies (or links) skills. An existing dir is replaced only if chandlery put it there, or with force.
export function install({ clients = ["claude"], scope = "project", only, exclude = [], link = false, force = false, dryRun = false, project, home, version = "dev" } = {}) {
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
