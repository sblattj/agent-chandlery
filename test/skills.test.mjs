import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, existsSync, mkdirSync, writeFileSync, lstatSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import * as skills from "../lib/skills.mjs";

const tmp = () => mkdtempSync(join(tmpdir(), "chandlery-skills-"));

test("every bundled skill has a SKILL.md whose name matches its folder and a short description", () => {
  const all = skills.list();
  assert.ok(all.length >= 1);
  for (const s of all) {
    assert.equal(s.name, s.dir.split("/").pop(), `${s.dir}: frontmatter name`);
    assert.ok(s.description && s.description.length > 20, `${s.name}: description`);
    assert.ok(s.description.length <= 600, `${s.name}: description is ${s.description.length} chars (cap 600)`);
  }
});

test("install copies into each client's project dir with an ownership mark", () => {
  const project = tmp();
  const r = skills.install({ clients: ["claude", "kiro", "codex"], project, only: ["goal-state"] });
  assert.equal(r.length, 3);
  for (const rel of [".claude/skills", ".kiro/skills", ".agents/skills"]) {
    assert.ok(existsSync(join(project, rel, "goal-file-autonomous-run-until-evidence", "SKILL.md")), rel);
    assert.ok(existsSync(join(project, rel, "goal-file-autonomous-run-until-evidence", ".chandlery.json")), rel);
  }
});

test("install never replaces a skill it did not put there unless forced", () => {
  const project = tmp();
  const dst = join(project, ".claude/skills/goal-file-autonomous-run-until-evidence");
  mkdirSync(dst, { recursive: true });
  writeFileSync(join(dst, "SKILL.md"), "mine");
  const r = skills.install({ project, only: ["goal-state"] });
  assert.match(r[0].action, /skip/);
  assert.equal(readFileSync(join(dst, "SKILL.md"), "utf8"), "mine");
  skills.install({ project, only: ["goal-state"], force: true });
  assert.notEqual(readFileSync(join(dst, "SKILL.md"), "utf8"), "mine");
});

test("install --link symlinks, user scope resolves under home, dry run writes nothing", () => {
  const home = tmp();
  skills.install({ scope: "user", home, link: true, only: ["goal-state"] });
  assert.ok(lstatSync(join(home, ".claude/skills/goal-file-autonomous-run-until-evidence")).isSymbolicLink());
  const project = tmp();
  skills.install({ project, dryRun: true });
  assert.ok(!existsSync(join(project, ".claude")));
});

test("unknown skill and unknown client fail loudly", () => {
  assert.throws(() => skills.install({ project: tmp(), only: ["nope"] }), /no such skill/);
  assert.throws(() => skills.install({ project: tmp(), clients: ["vim"] }), /unknown client/);
});

test("old skill names still work as --only aliases and resolve to the new folder", () => {
  const project = tmp();
  const a = skills.install({ project, only: ["goal-state"], dryRun: true });
  const b = skills.install({ project, only: ["goal-file-autonomous-run-until-evidence"], dryRun: true });
  assert.equal(a[0].skill, "goal-file-autonomous-run-until-evidence");
  assert.equal(a[0].dst, b[0].dst);
  assert.throws(() => skills.install({ project, only: ["no-such-skill"], dryRun: true }), /no such skill/);
});

test("every alias points at a real skill folder and never shadows one", () => {
  const names = new Set(skills.list().map((s) => s.name));
  for (const [old, target] of Object.entries(skills.ALIASES)) {
    assert.ok(names.has(target), `alias ${old} -> ${target}: no such skill folder`);
    assert.ok(!names.has(old), `alias ${old} shadows a real skill folder`);
  }
});

test("renamed skills resolve from their old short names, including chained renames", () => {
  const project = tmp();
  const cases = {
    "swarm": "fanning-out-a-verified-read-only-swarm",
    "xx": "fanning-out-parallel-writers-with-verified-changes",
    "pr-ab-evidence": "proving-a-bugfix-pr-red-to-green",
    "sketch": "building-a-local-html-visual-explainer",
    "sketch-local-html-visual-explainer": "building-a-local-html-visual-explainer",
    "work-overview": "summarizing-what-someone-shipped-from-git-log",
    "work-overview-from-git-log": "summarizing-what-someone-shipped-from-git-log",
  };
  for (const [old, target] of Object.entries(cases)) {
    const a = skills.install({ project, only: [old], dryRun: true });
    const b = skills.install({ project, only: [target], dryRun: true });
    assert.equal(a[0].skill, target, old);
    assert.equal(a[0].dst, b[0].dst, old);
  }
  const ex = skills.install({ project, exclude: ["swarm"], dryRun: true });
  assert.ok(!ex.some((r) => r.skill === "fanning-out-a-verified-read-only-swarm"), "--exclude takes old names too");
});
