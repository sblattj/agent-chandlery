export const meta = {
  name: 'swarm',
  description: 'Fan out units on lean agents (Haiku first), verify every claim, optionally double-verify with --compare',
  whenToUse: 'Run via /swarm (read-only) or /xx (write). Pass args {goal, mode, compare, units|claims}.',
  phases: [
    { title: 'Work', detail: 'one agent per unit, cheapest tier that fits' },
    { title: 'Verify', detail: 'Haiku skeptic per claim' },
    { title: 'Compare', detail: 'second independent verifier on a different tier (--compare only)' },
    { title: 'Synthesize', detail: 'Sonnet rollup' },
  ],
}

// args: {goal, mode:'read'|'write', compare:bool, verify_tier?, compare_tier?, synth?:bool,
//        units?:[{id, prompt, tier?, needs_mcp?, owns?:[abs paths], worktree?:abs path, isolate?:bool}],
//        claims?:[{id, claim, evidence?}]}   // claims = verify-only run, no Work phase
const A = args || {}
const MODE = A.mode === 'write' ? 'write' : 'read'
const COMPARE = !!A.compare
const VT = A.verify_tier || 'haiku'
const CT = A.compare_tier || (VT === 'haiku' ? 'sonnet' : 'haiku')
const TIERS = ['haiku', 'sonnet', 'opus']
const tier = t => (TIERS.includes(t) ? t : 'haiku')
// Pin the cheap tier to an exact model id: a bare 'haiku' alias can resolve to an older model than intended.
// Change the id here if you want a different cheap model.
const MODEL = t => (t === 'haiku' ? 'claude-haiku-5-5' : t)

const CLAIMS = {
  type: 'object',
  properties: {
    claims: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          claim: { type: 'string', description: 'one falsifiable sentence' },
          evidence: { type: 'string', description: 'file:line, command + output excerpt, or URL that proves it' },
          key: { type: 'string', description: 'stable short id: file:line or kebab-case topic' },
        },
        required: ['claim', 'evidence'],
      },
    },
    changed_files: { type: 'array', items: { type: 'string' } },
    notes: { type: 'string' },
  },
  required: ['claims'],
}
const VERDICT = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['confirmed', 'refuted', 'unclear'] },
    reason: { type: 'string', description: 'what you checked and what you saw, under 300 chars' },
  },
  required: ['verdict', 'reason'],
}

const RO = 'READ-ONLY RUN: do not edit, write, commit, push, post, or call any mutating API. Shell reads only (cat, grep, git log/show/diff, curl GET). If the task seems to need a write, report it as a claim instead.'
const wrules = u => [
  'WRITE RUN. Workspace: ' + (u.worktree || '(isolated worktree provided by the harness; stay inside cwd)'),
  'You own ONLY these files: ' + JSON.stringify(u.owns || []) + '. Ask (report in notes) before touching anything else.',
  'Sibling ownership map: ' + JSON.stringify((A.units || []).filter(x => x.id !== u.id).map(x => ({ id: x.id, owns: x.owns || [] }))),
  'Other agents are editing this worktree concurrently. Changes in their declared files are expected. Preserve them, do not edit or revert them, and continue your assigned work. A dirty git status alone is not a conflict.',
  'Never push, force-push, merge, post, or publish. Commit only if the unit prompt says so. Bound long commands with perl -e \'alarm 600; exec @ARGV\'.',
  'Report each change and each test result as a claim with evidence (file:line, or command + exit code + last lines).',
].join('\n')

const agentType = u => (u.needs_mcp ? 'general-purpose' : 'lean')

function workPrompt(u) {
  return [
    'Goal: ' + (A.goal || ''),
    'Your unit (' + u.id + '): ' + u.prompt,
    MODE === 'write' ? wrules(u) : RO,
    'Return claims: each one falsifiable sentence with concrete evidence. No claim without evidence. Prefer fewer, solid claims.',
  ].join('\n\n')
}
function verifyPrompt(c, lens) {
  return [
    'You are a skeptic. Try to REFUTE this claim by checking the evidence yourself (open the file, rerun the read-only command). ' + RO,
    'Context (paths in the claim are relative to dirs named here): ' + (A.goal || ''),
    'Lens: ' + lens,
    'Claim: ' + c.claim,
    'Evidence given: ' + (c.evidence || '(none)'),
    'confirmed = you reproduced the evidence and it supports the claim. refuted = evidence is wrong or contradicts it. unclear = could not check. Default to unclear, never guess confirmed.',
  ].join('\n\n')
}

async function verifyClaim(c, unitId) {
  const v1 = await agent(verifyPrompt(c, 'does the evidence exist and say what is claimed'), {
    label: 'verify:' + unitId + ':' + c.id, phase: 'Verify', model: MODEL(VT), agentType: 'lean', schema: VERDICT, effort: 'low',
  })
  const out = { ...c, unit: unitId, verdict: v1 ? v1.verdict : 'unclear', reason: v1 ? v1.reason : 'verifier died' }
  if (!COMPARE) return out
  const v2 = await agent(verifyPrompt(c, 'independent recheck: look for a counterexample or a newer state that contradicts it'), {
    label: 'compare:' + unitId + ':' + c.id, phase: 'Compare', model: MODEL(CT), agentType: 'lean', schema: VERDICT,
  })
  out.verdict2 = v2 ? v2.verdict : 'unclear'
  out.reason2 = v2 ? v2.reason : 'verifier died'
  out.agree = out.verdict === out.verdict2
  return out
}

const idify = (u, cs) => (cs || []).map((c, i) => ({ ...c, id: c.key || u.id + '-' + (i + 1) }))

let units = []
let verified = []
if (Array.isArray(A.claims) && A.claims.length) {
  const u = { id: 'given' }
  const cs = A.claims.map((c, i) => ({ ...c, id: c.id || c.key || 'c' + (i + 1) }))
  verified = (await parallel(cs.map(c => () => verifyClaim(c, 'given')))).filter(Boolean)
  units = [{ id: 'given', tier: 'n/a', claims: cs.length }]
} else {
  const list = (A.units || []).map(u => ({ ...u, tier: tier(u.tier) }))
  const owned = list.flatMap(u => u.owns || [])
  const overlap = MODE === 'write' && new Set(owned).size !== owned.length
  if (overlap) log('ownership overlaps: writers run sequentially')
  const runUnit = u => agent(workPrompt(u), {
    label: 'work:' + u.id, phase: 'Work', model: MODEL(u.tier), agentType: agentType(u), schema: CLAIMS,
    ...(MODE === 'write' && u.isolate ? { isolation: 'worktree' } : {}),
  })
  const verifyUnit = (r, u) => {
    units.push({ id: u.id, tier: u.tier, agentType: agentType(u), claims: r ? r.claims.length : 0, changed_files: (r && r.changed_files) || [], notes: (r && r.notes) || (r ? '' : 'unit died') })
    return parallel(idify(u, r && r.claims).map(c => () => verifyClaim(c, u.id)))
  }
  if (overlap) {
    for (const u of list) verified.push(...((await verifyUnit(await runUnit(u), u)) || []))
  } else {
    verified = (await pipeline(list, u => runUnit(u), (r, u) => verifyUnit(r, u))).flat()
  }
  verified = verified.filter(Boolean)
}

const count = (k, v) => verified.filter(c => c[k] === v).length
const stats = {
  claims: verified.length,
  confirmed: count('verdict', 'confirmed'),
  refuted: count('verdict', 'refuted'),
  unclear: count('verdict', 'unclear'),
}
if (COMPARE) {
  stats.disagreements = verified.filter(c => !c.agree).length
  stats.agreement = verified.length ? +(1 - stats.disagreements / verified.length).toFixed(3) : null
  stats.double_confirmed = verified.filter(c => c.verdict === 'confirmed' && c.verdict2 === 'confirmed').length
}
log('claims ' + stats.claims + ': ' + stats.confirmed + ' confirmed, ' + stats.refuted + ' refuted, ' + stats.unclear + ' unclear' + (COMPARE ? ', ' + stats.disagreements + ' disagreements' : ''))

let summary = ''
if (A.synth !== false && verified.length) {
  summary = await agent(
    'Goal: ' + (A.goal || '') + '\n\nCounts are fixed, copy them verbatim and never recount: ' + JSON.stringify(stats) + '\n\nWrite a short markdown rollup of these verified claims: what is confirmed, what got refuted and why, and every verifier disagreement (those need a human look). Under 400 words.\n\n' + JSON.stringify(verified),
    { label: 'synthesize', phase: 'Synthesize', model: 'sonnet', agentType: 'lean' })
}
return { goal: A.goal || '', mode: MODE, compare: COMPARE, tiers: { verify: VT, compare: COMPARE ? CT : null }, units, stats, claims: verified, summary }
