// Goal state: one JSON file per project that keeps an agent working on one objective until it is
// achieved with evidence, a concrete blocker is recorded, a budget runs out, or a human pauses it.
// Design source: the session-scoped /goal workflow of opencode-goal-pro-max-complete-plugin (same author),
// rebuilt client-neutral: no host plugin API, just a file, a CLI and an optional stop hook.
import { readFileSync, writeFileSync, renameSync, mkdirSync, existsSync, appendFileSync, chmodSync } from "node:fs";
import { dirname, resolve } from "node:path";

export const SCHEMA = "chandlery.goal/1";
export const STATES = ["active", "paused", "blocked", "achieved"];
export const ACTION_STATUS = ["pending", "in_progress", "done", "blocked"];
export const DEFAULT_BUDGET = { maxTurns: 0, maxMinutes: 480, maxTokens: 0, wrapupRatio: 0.8, stallTurns: 10 };

export const goalPath = (p) => resolve(p || process.env.CHANDLERY_GOAL_FILE || ".chandlery/goal.json");
const now = () => new Date().toISOString();
const nonEmpty = (s) => typeof s === "string" && s.trim().length > 0;

export function load(file) {
  const f = goalPath(file);
  if (!existsSync(f)) return null;
  return JSON.parse(readFileSync(f, "utf8"));
}

// Atomic write (temp + rename), owner-only, plus one ledger line per event so history survives a bad write.
export function save(goal, file, event) {
  const f = goalPath(file);
  mkdirSync(dirname(f), { recursive: true, mode: 0o700 });
  goal.updatedAt = now();
  if (event) {
    const entry = { at: goal.updatedAt, ...event };
    goal.history = [...(goal.history || []), entry].slice(-200);
    appendFileSync(f + ".ledger.jsonl", JSON.stringify(entry) + "\n", { mode: 0o600 });
  }
  const tmp = `${f}.tmp-${process.pid}`;
  writeFileSync(tmp, JSON.stringify(goal, null, 2) + "\n", { mode: 0o600 });
  renameSync(tmp, f);
  try { chmodSync(f, 0o600); } catch {}
  return goal;
}

export function create({ objective, brief, success = [], constraints = [], mode = "normal", budget = {} }) {
  if (!nonEmpty(objective) && !nonEmpty(brief)) throw new Error("an objective is required");
  const text = nonEmpty(brief) ? brief : objective;
  const label = nonEmpty(objective) ? objective.split("\n")[0].trim() : text.split("\n").find(nonEmpty).trim();
  return {
    schema: SCHEMA,
    objective: label.slice(0, 120),
    brief: text,
    success: [].concat(success).filter(nonEmpty),
    constraints: [].concat(constraints).filter(nonEmpty),
    mode,
    state: "active",
    stopReason: null,
    blocker: null,
    budget: { ...DEFAULT_BUDGET, ...budget },
    usage: { turns: 0, tokens: 0, windowStartedAt: now(), stalled: 0, lastFingerprint: null, wrapupSent: false },
    actions: [],
    completion: null,
    history: [],
    createdAt: now(),
    updatedAt: now(),
  };
}

// Every structural rule, as a list of problems; empty means valid.
export function validate(g) {
  const p = [];
  const need = (cond, msg) => { if (!cond) p.push(msg); };
  if (!g || typeof g !== "object") return ["not an object"];
  need(g.schema === SCHEMA, `schema must be "${SCHEMA}"`);
  need(nonEmpty(g.objective), "objective is empty");
  need(nonEmpty(g.brief), "brief is empty");
  need(STATES.includes(g.state), `state must be one of ${STATES.join(", ")}`);
  need(["normal", "ordered"].includes(g.mode), "mode must be normal or ordered");
  need(Array.isArray(g.success) && Array.isArray(g.constraints), "success and constraints must be arrays");
  need(Array.isArray(g.actions), "actions must be an array");
  const b = g.budget || {};
  for (const k of ["maxTurns", "maxMinutes", "maxTokens", "stallTurns"]) need(Number.isInteger(b[k]) && b[k] >= 0, `budget.${k} must be an integer >= 0 (0 = unlimited)`);
  need(typeof b.wrapupRatio === "number" && b.wrapupRatio > 0 && b.wrapupRatio <= 1, "budget.wrapupRatio must be in (0, 1]");
  const ids = new Set();
  for (const [i, a] of (g.actions || []).entries()) {
    const at = `actions[${i}]`;
    need(nonEmpty(a.id), `${at}.id is empty`);
    if (ids.has(a.id)) p.push(`${at}.id "${a.id}" is a duplicate`);
    ids.add(a.id);
    need(nonEmpty(a.title), `${at}.title is empty`);
    need(ACTION_STATUS.includes(a.status), `${at}.status must be one of ${ACTION_STATUS.join(", ")}`);
    if (a.status === "done") need(isVerified(a), `${at} is done without claim, evidence and verdict "pass"`);
    if (a.status === "blocked") need(nonEmpty(a.reason), `${at} is blocked without a reason`);
  }
  if (g.state === "blocked") need(nonEmpty(g.blocker), "state is blocked but blocker is empty");
  if (g.state === "achieved") {
    need(g.completion && nonEmpty(g.completion.summary) && nonEmpty(g.completion.evidence), "state is achieved without completion summary and evidence");
    need(openActions(g).length === 0, `state is achieved with open actions: ${openActions(g).map((a) => a.id).join(", ")}`);
  }
  return p;
}

export const isVerified = (a) => a.status === "done" && nonEmpty(a.claim) && nonEmpty(a.evidence) && a.verdict === "pass";
export const openActions = (g) => g.actions.filter((a) => !(isVerified(a) || (a.status === "blocked" && nonEmpty(a.reason))));

export function planAdd(g, id, title) {
  if (!nonEmpty(id) || !nonEmpty(title)) throw new Error("plan add needs an id and a title");
  if (g.actions.some((a) => a.id === id)) throw new Error(`action ${id} already exists`);
  g.actions.push({ id, title, status: "pending", claim: null, evidence: null, verdict: null, reason: null });
  return { event: "plan", note: `+${id} ${title}` };
}

// Moving an action to done needs claim + evidence + a passing verdict; blocked needs a reason.
// Fields already recorded are kept, so a re-plan can't launder a verified action back to unverified.
export function act(g, id, status, { claim, evidence, verdict, reason } = {}) {
  const a = g.actions.find((x) => x.id === id);
  if (!a) throw new Error(`no action ${id}`);
  if (!ACTION_STATUS.includes(status)) throw new Error(`status must be one of ${ACTION_STATUS.join(", ")}`);
  const next = { ...a, status, claim: claim ?? a.claim, evidence: evidence ?? a.evidence, verdict: verdict ?? a.verdict, reason: reason ?? a.reason };
  if (status === "done" && !isVerified(next)) throw new Error(`refused: ${id} needs --claim, --evidence and --verdict pass to be done`);
  if (status === "blocked" && !nonEmpty(next.reason)) throw new Error(`refused: ${id} needs --reason to be blocked`);
  Object.assign(a, next);
  return { event: "action", note: `${id} -> ${status}` };
}

export function complete(g, { summary, evidence }) {
  if (!nonEmpty(summary) || !nonEmpty(evidence)) throw new Error("refused: completion needs --summary and --evidence (an observation, not a self-report)");
  const open = openActions(g);
  if (open.length) throw new Error(`refused: open actions ${open.map((a) => a.id).join(", ")} (each must be done with a passing verdict, or blocked with a reason)`);
  g.state = "achieved";
  g.stopReason = "achieved";
  g.completion = { summary, evidence, at: now() };
  return { event: "achieved", note: summary };
}

export function block(g, reason) {
  if (!nonEmpty(reason)) throw new Error("refused: name the concrete blocker only the human can clear");
  g.state = "blocked";
  g.blocker = reason;
  g.stopReason = "blocked";
  return { event: "blocked", note: reason };
}

export function pause(g, why = "paused") {
  g.state = "paused";
  g.stopReason = why;
  return { event: "pause", note: why };
}

// Resume opens a fresh budget window: turns, tokens, clock and stall counters restart.
export function resume(g) {
  if (g.state === "achieved") throw new Error("goal is achieved; set a new one");
  g.state = "active";
  g.stopReason = null;
  g.blocker = null;
  g.usage = { ...g.usage, turns: 0, tokens: 0, windowStartedAt: now(), stalled: 0, wrapupSent: false };
  return { event: "resume" };
}

const fingerprint = (g) => JSON.stringify(g.actions.map((a) => [a.id, a.status, a.verdict, a.evidence]));

export function budgetUse(g, at = Date.now()) {
  const b = g.budget, u = g.usage;
  const minutes = (at - Date.parse(u.windowStartedAt)) / 60000;
  const parts = [
    ["turns", u.turns, b.maxTurns],
    ["minutes", minutes, b.maxMinutes],
    ["tokens", u.tokens, b.maxTokens],
  ].filter(([, , max]) => max > 0).map(([name, used, max]) => ({ name, used, max, ratio: used / max }));
  const top = parts.sort((x, y) => y.ratio - x.ratio)[0] || null;
  return { minutes, parts, top };
}

// One agent turn ended. Decide: continue, wrap up (one handoff turn), or stop. Mutates usage.
export function turn(g, { tokens = 0, at = Date.now() } = {}) {
  if (g.state !== "active") return { decision: "stop", why: g.stopReason || g.state };
  g.usage.turns += 1;
  g.usage.tokens += Math.max(0, Number(tokens) || 0);
  const fp = fingerprint(g);
  g.usage.stalled = fp === g.usage.lastFingerprint ? g.usage.stalled + 1 : 0;
  g.usage.lastFingerprint = fp;
  const { top } = budgetUse(g, at);
  if (top && top.ratio >= 1) { pause(g, `budget: ${top.name} limit reached`); return { decision: "stop", why: g.stopReason, event: "limit" }; }
  if (g.budget.stallTurns > 0 && g.usage.stalled >= g.budget.stallTurns) {
    pause(g, `stalled: plan unchanged for ${g.usage.stalled} turns`);
    return { decision: "stop", why: g.stopReason, event: "limit" };
  }
  if (top && top.ratio >= g.budget.wrapupRatio) {
    if (g.usage.wrapupSent) { pause(g, `budget wrap-up: ${top.name} at ${Math.round(top.ratio * 100)}%`); return { decision: "stop", why: g.stopReason, event: "limit" }; }
    g.usage.wrapupSent = true;
    return { decision: "wrapup", why: `${top.name} at ${Math.round(top.ratio * 100)}% of budget` };
  }
  return { decision: "continue" };
}

const fmtBudget = (g) => budgetUse(g).parts.map((p) => `${p.name} ${Math.round(p.used)}/${p.max}`).join(", ") || "unbounded";

export function status(g) {
  const lines = [
    `Goal: ${g.objective}`,
    `State: ${g.state}${g.stopReason && g.state !== "active" ? ` (${g.stopReason})` : ""}`,
    `Budget: ${fmtBudget(g)}`,
  ];
  if (g.blocker) lines.push(`Blocker: ${g.blocker}`);
  if (g.actions.length) {
    const verified = g.actions.filter(isVerified).length;
    lines.push(`Plan: ${verified}/${g.actions.length} verified`);
    for (const a of g.actions) lines.push(`  [${isVerified(a) ? "x" : a.status === "blocked" ? "!" : a.status === "in_progress" ? ">" : " "}] ${a.id} ${a.title}${a.status === "blocked" ? ` (blocked: ${a.reason})` : ""}`);
  }
  if (g.completion) lines.push(`Achieved: ${g.completion.summary}`, `Evidence: ${g.completion.evidence}`);
  return lines.join("\n");
}

// The text fed back to the agent at the end of a turn (stop hook) or pasted by hand.
export function continuationPrompt(g, decision = "continue", cli = "chandlery goal") {
  const open = openActions(g);
  const head = decision === "wrapup"
    ? `Goal budget is nearly spent. Do not start new work. Write a handoff: what is done (with evidence), what remains, the next concrete step. Then run \`${cli} pause\`.`
    : `Keep working on the goal. Do not stop until it is achieved with evidence or truly blocked.`;
  const parts = [
    head,
    "",
    `Objective: ${g.objective}`,
    g.brief !== g.objective ? `Brief:\n${g.brief}` : null,
    g.success.length ? `Success criteria:\n${g.success.map((s) => `- ${s}`).join("\n")}` : null,
    g.constraints.length ? `Constraints:\n${g.constraints.map((s) => `- ${s}`).join("\n")}` : null,
    g.mode === "ordered" ? "Mode: ordered. Do the steps in the order given." : null,
    `Budget: ${fmtBudget(g)}`,
    g.actions.length
      ? `Plan (${g.actions.length - open.length}/${g.actions.length} closed). Open:\n${open.map((a) => `- ${a.id} [${a.status}] ${a.title}`).join("\n") || "- none"}`
      : `No plan yet. Break the goal into actions: \`${cli} plan add <id> "<title>"\`.`,
    "",
    "CEV rule: each action needs a Claim, the smallest Evidence that could prove or break it (command output, file content, an HTTP response; never your own report), and a Verdict.",
    `Close an action: \`${cli} act <id> done --claim "..." --evidence "..." --verdict pass\`.`,
    `Finish: \`${cli} complete --summary "..." --evidence "..."\`. Truly stuck on something only the human can give (a credential, an irreversible call): \`${cli} block "<the blocker>"\`. A question that doesn't stop all progress is not a blocker; note it and keep going.`,
  ];
  return parts.filter((x) => x !== null).join("\n");
}
