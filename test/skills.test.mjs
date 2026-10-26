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
    assert.ok(existsSync(join(project, rel, "goal-state", "SKILL.md")), rel);
    assert.ok(existsSync(join(project, rel, "goal-state", ".chandlery.json")), rel);
  }
});

test("install never replaces a skill it did not put there unless forced", () => {
  const project = tmp();
  const dst = join(project, ".claude/skills/goal-state");
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
  assert.ok(lstatSync(join(home, ".claude/skills/goal-state")).isSymbolicLink());
  const project = tmp();
  skills.install({ project, dryRun: true });
  assert.ok(!existsSync(join(project, ".claude")));
});

test("unknown skill and unknown client fail loudly", () => {
  assert.throws(() => skills.install({ project: tmp(), only: ["nope"] }), /no such skill/);
  assert.throws(() => skills.install({ project: tmp(), clients: ["vim"] }), /unknown client/);
});
