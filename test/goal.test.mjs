import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, statSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import * as goal from "../lib/goal.mjs";

const CLI = new URL("../bin/chandlery.mjs", import.meta.url).pathname;
const tmp = () => mkdtempSync(join(tmpdir(), "chandlery-"));
const run = (cwd, args, input) => spawnSync(process.execPath, [CLI, ...args], { cwd, input, encoding: "utf8", env: { ...process.env, CHANDLERY_GOAL_FILE: "" } });

test("a new goal is valid and active with the default budget", () => {
  const g = goal.create({ objective: "ship it" });
  assert.deepEqual(goal.validate(g), []);
  assert.equal(g.state, "active");
  assert.equal(g.budget.maxMinutes, 480);
  assert.equal(g.budget.maxTurns, 0);
});

test("a long brief keeps its text verbatim and labels from its first line", () => {
  const brief = "Fix the parser\n\nrun: git push --force -- --max-turns 3\n";
  const g = goal.create({ brief });
  assert.equal(g.brief, brief);
  assert.equal(g.objective, "Fix the parser");
});

test("done is refused without claim, evidence and a passing verdict", () => {
  const g = goal.create({ objective: "x" });
  goal.planAdd(g, "a1", "build");
  assert.throws(() => goal.act(g, "a1", "done", { claim: "builds" }), /needs --claim, --evidence and --verdict pass/);
  assert.throws(() => goal.act(g, "a1", "done", { claim: "builds", evidence: "exit 0", verdict: "fail" }), /refused/);
  goal.act(g, "a1", "done", { claim: "builds", evidence: "exit 0", verdict: "pass" });
  assert.ok(goal.isVerified(g.actions[0]));
});

test("blocked actions need a reason", () => {
  const g = goal.create({ objective: "x" });
  goal.planAdd(g, "a1", "deploy");
  assert.throws(() => goal.act(g, "a1", "blocked"), /--reason/);
  goal.act(g, "a1", "blocked", { reason: "needs a prod credential" });
  assert.equal(g.actions[0].status, "blocked");
});

test("re-marking an action keeps evidence already recorded", () => {
  const g = goal.create({ objective: "x" });
  goal.planAdd(g, "a1", "t");
  goal.act(g, "a1", "done", { claim: "c", evidence: "e", verdict: "pass" });
  goal.act(g, "a1", "done", {});
  assert.equal(g.actions[0].evidence, "e");
});

test("completion needs summary, evidence and no open actions", () => {
  const g = goal.create({ objective: "x" });
  goal.planAdd(g, "a1", "t");
  assert.throws(() => goal.complete(g, { summary: "done" }), /--summary and --evidence/);
  assert.throws(() => goal.complete(g, { summary: "done", evidence: "tests pass" }), /open actions a1/);
  goal.act(g, "a1", "done", { claim: "c", evidence: "e", verdict: "pass" });
  goal.complete(g, { summary: "done", evidence: "npm test: 12 passing" });
  assert.equal(g.state, "achieved");
  assert.deepEqual(goal.validate(g), []);
});

test("block needs a concrete blocker", () => {
  const g = goal.create({ objective: "x" });
  assert.throws(() => goal.block(g, " "), /concrete blocker/);
  goal.block(g, "needs the signing key");
  assert.equal(g.state, "blocked");
});

test("validate catches a hand-edited done action with no evidence", () => {
  const g = goal.create({ objective: "x" });
  g.actions.push({ id: "a1", title: "t", status: "done", claim: "c", evidence: null, verdict: "pass" });
  g.actions.push({ id: "a1", title: "dup", status: "pending" });
  const p = goal.validate(g);
  assert.ok(p.some((s) => /done without claim/.test(s)));
  assert.ok(p.some((s) => /duplicate/.test(s)));
});

test("turn: continue, then wrap-up once at the ratio, then stop", () => {
  const g = goal.create({ objective: "x", budget: { maxTurns: 10 } });
  for (let i = 0; i < 7; i++) {
    goal.planAdd(g, `a${i}`, "t"); // plan changes each turn, so no stall
    assert.equal(goal.turn(g).decision, "continue");
  }
  goal.planAdd(g, "a7", "t");
  assert.equal(goal.turn(g).decision, "wrapup");
  goal.planAdd(g, "a8", "t");
  const r = goal.turn(g);
  assert.equal(r.decision, "stop");
  assert.equal(g.state, "paused");
  assert.match(g.stopReason, /wrap-up/);
});

test("turn: the clock budget stops a goal past its window", () => {
  const g = goal.create({ objective: "x", budget: { maxMinutes: 1 } });
  const later = Date.parse(g.usage.windowStartedAt) + 2 * 60000;
  const r = goal.turn(g, { at: later });
  assert.equal(r.decision, "stop");
  assert.match(g.stopReason, /minutes limit/);
});

test("turn: an unchanged plan for stallTurns pauses the goal", () => {
  const g = goal.create({ objective: "x", budget: { stallTurns: 3 } });
  goal.turn(g);
  goal.turn(g);
  goal.turn(g);
  const r = goal.turn(g);
  assert.equal(r.decision, "stop");
  assert.match(g.stopReason, /stalled/);
});

test("resume opens a fresh budget window", () => {
  const g = goal.create({ objective: "x", budget: { maxTurns: 1 } });
  goal.turn(g);
  assert.equal(g.state, "paused");
  goal.resume(g);
  assert.equal(g.state, "active");
  assert.equal(g.usage.turns, 0);
});

test("CLI: set, plan, act, complete round trip with a ledger and 0600 file", () => {
  const d = tmp();
  assert.equal(run(d, ["goal", "set", "make", "tests", "pass", "--success", "npm test green"]).status, 0);
  assert.equal(run(d, ["goal", "plan", "add", "a1", "fix", "parser"]).status, 0);
  const refused = run(d, ["goal", "complete", "--summary", "s", "--evidence", "e"]);
  assert.equal(refused.status, 1);
  assert.match(refused.stderr, /open actions a1/);
  assert.equal(run(d, ["goal", "act", "a1", "done", "--claim", "parser fixed", "--evidence", "node --test: 4 pass", "--verdict", "pass"]).status, 0);
  const done = run(d, ["goal", "complete", "--summary=all green", "--evidence=npm test: 4 pass"]);
  assert.equal(done.status, 0, done.stderr);
  assert.match(done.stdout, /State: achieved/);
  const f = join(d, ".chandlery", "goal.json");
  assert.equal(statSync(f).mode & 0o777, 0o600);
  assert.equal(run(d, ["goal", "validate"]).stdout.trim(), "valid");
  const ledger = readFileSync(f + ".ledger.jsonl", "utf8").trim().split("\n").map((l) => JSON.parse(l).event);
  assert.deepEqual(ledger, ["set", "plan", "action", "achieved"]);
});

test("CLI: rejects a bad budget value", () => {
  const r = run(tmp(), ["goal", "set", "x", "--max-turns", "-2"]);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /integer >= 0/);
});

test("Claude stop hook blocks while active and goes quiet once achieved", () => {
  const d = tmp();
  run(d, ["goal", "set", "x"]);
  const r = run(d, ["goal", "hook", "claude"], JSON.stringify({ cwd: d, stop_hook_active: false }));
  assert.equal(r.status, 0, r.stderr);
  const out = JSON.parse(r.stdout);
  assert.equal(out.decision, "block");
  assert.match(out.reason, /Keep working on the goal/);
  run(d, ["goal", "complete", "--summary", "s", "--evidence", "e"]);
  const quiet = run(d, ["goal", "hook", "claude"], JSON.stringify({ cwd: d }));
  assert.equal(quiet.stdout, "");
});

test("Claude stop hook is silent with no goal file", () => {
  const d = tmp();
  const r = run(d, ["goal", "hook", "claude"], JSON.stringify({ cwd: d }));
  assert.equal(r.status, 0);
  assert.equal(r.stdout, "");
  assert.ok(!existsSync(join(d, ".chandlery")));
});

test("hook install adds the Stop hook once", () => {
  const d = tmp();
  run(d, ["goal", "hook", "install", "--project", d]);
  const again = run(d, ["goal", "hook", "install", "--project", d]);
  assert.match(again.stdout, /already present/);
  const s = JSON.parse(readFileSync(join(d, ".claude", "settings.json"), "utf8"));
  assert.equal(s.hooks.Stop.length, 1);
});
