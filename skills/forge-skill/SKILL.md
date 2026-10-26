---
name: forge-skill
description: "Turn what just happened in a session into a reusable skill, or harden an existing one, by mining the friction (repeated manual steps, dead-ends, non-obvious flags, decisions the user had to make) into a fast shortcut. Triggers on: make a skill for this, turn this into a skill, create a reusable skill, skillify this, add a skill, harden a skill, improve a skill, mine this session for a skill, capture this workflow, so I can do this faster next time."
---

# forge-skill: mine session friction into a skill

Use when a task in this session is worth repeating and you want the *next* session to do it
in one step instead of re-deriving it. Works for both **new** skills and **hardening** an
existing one. The value is not just the main-path commands; it's the friction: the wrong
turns, the non-obvious flags, the gotchas, and the decisions the user was forced to make.

## Procedure

1. **Name the repeatable task** in one sentence ("check my PRs for activity since I pushed",
   "prove a bug-fix PR with red/green evidence"). If it isn't repeatable, don't forge a skill.
2. **Decide new vs harden.** List existing skills (`ls ~/.claude/skills`, or your client's skills
   dir, plus the project's own skills dir) and read any whose
   description overlaps. Harden if one already owns this area (add the missing case / gotcha /
   cross-ref); create new only for a genuinely distinct task. Never make a near-duplicate.
3. **Mine the friction** from the transcript (see checklist below). This is the core step.
4. **Extract the commands that actually worked**: copy the real, tested invocations, not a
   cleaned-up guess. If the runtime logic is more than a couple of lines, put it in a helper
   script in the skill dir rather than inlining fragile commands in prose.
5. **Write `SKILL.md`** with the frontmatter + structure below.
6. **Validate before claiming done**: run the helper script / commands and confirm real
   output. A skill that was never executed is a draft, not a skill. Fix and re-run.
7. **Cross-link** related skills (a `## Related` section both ways) so they compose.
8. **Skill descriptions cost context.** Every fully listed skill's description rides along in
   every session, so a new skill is a standing token cost until it earns its place. If the client
   supports it, **start new skills on probation**: in Claude Code, add `"<name>": "name-only"` under
   `skillOverrides` in `settings.json` (back it up first). Name-only still fires (an A/B showed the
   same recall) but costs no description tokens. `skill-diet-audit` suggests promoting it to `on`
   after more than 3 uses. Skip this when the user will only ever type `/name` (use
   `user-invocable-only`) or asks for it fully listed. Clients without such a setting: keep the
   description tight instead.

9. **Find where the skill really lives before writing.** If `readlink ~/.claude/skills/<sibling>`
   points into a repo (a dotfiles or skills repo), create the new skill there and link it back, then
   commit and sync that repo. If that repo is public, scrub employer names, internal repos and ticket
   ids first (a first draft cited a work repo and a work-only skill). If settings that hold
   `skillOverrides` are shared across machines, expect merge conflicts on pull when another machine
   also added entries: keep both sides, then validate the JSON (`jq -e .`).

**Other clients (Codex, Kiro, OpenCode):** inspect the client's skill catalog and resolve symlinks
to the owning source before editing. Claude command Markdown, inline shell expansion, session IDs
and `skillOverrides` do not transfer automatically. Use a native `SKILL.md`, install or link it
where that client looks, and verify the installed link. Keep any slash prompt a thin pointer to
that one skill. For session mining, open the exact session transcript by its ID or path; do not
grab the newest transcript, and do not read one client's usage counts as another's.

## What "friction" to mine (the checklist)

Scan the session for anything that cost extra turns or nearly went wrong: that is exactly
what the skill should pre-empt:

- **Repeated manual steps** you did more than once (fold into one script/command).
- **Dead-ends and errors** that cost a retry: a wrong flag, a tool that returned empty, a
  build that failed until a specific fix. Record the *fix*, not just the symptom.
- **Non-obvious flags / API shapes**: e.g. `gh api --paginate --jq` filters per page, and its
  `--jq` cannot be combined with `--slurp` (gh errors), so aggregate across pages with
  `gh api ... --paginate --slurp | jq ...` (an EXTERNAL jq); a CDP `evaluate_script` tool needs
  an invoked IIFE (a bare `() => ...` returns the function).
- **Side effects the user had to be warned about**: e.g. re-requesting a reviewer resets a
  standing approval; a push flagged Dependabot alerts.
- **Decisions the user was forced to make** (and the right default): which anchor, which
  branch, take-upstream vs downgrade, cascade vs reclaim a slot.
- **Environment specifics**: exact repo/branch, the "usual" people/values, tool availability
  (shellcheck present, pyyaml absent -> use ruby), where auth lives (browser logged in as X).
  Make these arguments or env vars with sensible defaults, not hard-coded values.
- **The user's standing preferences** relevant here (from their AGENTS.md / CLAUDE.md: tone,
  package manager, banned words) so the skill's output already conforms.

Write each finding as "do X (because Y bit us)" so the reason survives.

## SKILL.md structure

```
---
name: <kebab-case, matches the folder>
description: "<one line: what it does + a rich set of trigger phrases a user would actually
  type>. Triggers on: <comma-separated natural phrases>."
---

# <Title>

<One or two lines: what it answers / produces.>

## Do this
<The command(s) or `~/.claude/skills/<name>/<script>.sh`. Lead with the fast path.>

## Why it's built this way (friction mined)
<The gotchas as bullets: the payload that makes the skill better than winging it.>

## Related
<Sibling skills that compose with this one.>
```

Rules that make a skill actually fire and actually help:
- **The `description` is the trigger surface.** Pack it with the real phrasings the user
  says, not a formal summary; matching is on this text. Include the repo/domain if scoped.
- **Cap `description` + `when_to_use` at 600 chars.** Every description sits in every
  session's context (one measured setup: the skills list alone cost 5.6k tokens). Keep the most
  distinctive triggers (exact error strings, unique names, the commonest plain asks) and put
  the rest in a `## More triggers` line right after the frontmatter. When hardening, swap a
  weaker trigger out rather than growing past the cap.
- **Lead with the fast path.** The first thing in "Do this" should be the single command.
- **Prefer a helper script** for anything non-trivial: `chmod +x`, take optional args + env
  overrides for the environment-specific bits (repo, the "usual" set), default sensibly, and
  keep it **read-only** unless the user asks for a mutation. Print mutating commands for the
  user to run rather than auto-running outward actions.
- **Keep it tight.** A skill is a shortcut, not a manual; link canonical docs, don't restate.

## New vs harden: bias

Harden the existing skill when the task is a variant, an added case, or a fresh gotcha for an
area a skill already owns; the win is usually a better `description` (more triggers) plus one
new gotcha or cross-ref. Create new only for a distinct task. When you harden, also add the
newly-discovered trigger phrases to the description so it fires next time (within the
600-char cap; overflow goes to `## More triggers`).

## Validate + report

Run it. Show the real output. Then tell the user: the skill name, where it lives, its trigger
phrases, and (if you hardened) what changed. If the helper mutates anything, say so and that
it defaults to read-only.

## Related

- `pr-activity-since-push`, `pr-ab-evidence`, `swarm` were all forged/hardened with this process
  and are good worked examples of the structure.
- `skill-diet-audit`: the 600-char cap check and the probation-to-`on` promotion.
- `skill-trigger-ab`: measure whether a trimmed or name-only description still fires.
