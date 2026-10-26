---
name: evidence-dump
description: "Dump your shipped-work evidence into one folder for reconciling commitments: GitHub PRs via gh (all states), Azure DevOps PRs via az (with the org/project flags that otherwise print nothing), git log on all branches since a date for each repo, an optional dated notes/transcript folder list, and a MANIFEST. Read-only; repos, since-date and tracker are arguments. Triggers on: dump my evidence, what have I shipped since, gather my PRs and commits, evidence folder for reconcile, list my ADO PRs, prove what I did, commits and PRs since September."
---

# evidence-dump

## Do this

```bash
D=${SKILL_DIR:-~/.claude/skills/evidence-dump}/dump.sh
$D                                                     # cwd repo, last 30 days, git user.name
$D --since 2026-09-01 --out ./evidence ~/dev/acme-api ~/dev/acme-web
$D --author "Jane Doe" --gh-repo my-org/my-repo        # a GitHub repo with no local checkout
ADO_ORG=<org URL> ADO_PROJECT='<project>' $D --ado-repo <repo>   # Azure DevOps, no checkout
$D --ws ~/notes/meetings ~/dev/acme-api                # also list dated folders (YYYY-MM-DD-HHMM...)
```

Nothing is baked in. Repos: args, else `EVIDENCE_REPOS` (space-separated), else the repo containing cwd (none: exit 2). Since: `--since` / `EVIDENCE_SINCE`, else 30 days ago. PR sources (the tracker) come from each repo's origin: GitHub remotes get `gh pr list`, Azure DevOps remotes (`https://<host>/<org>/<project>/_git/<repo>` or the `ssh.<host>:v3/<org>/<project>/<repo>` form) get `az repos pr list` with org/project parsed from the URL. `--gh-repo` / `--ado-repo` add sources without a checkout; `--ado-repo` needs env `ADO_ORG` (your Azure DevOps organization URL, as `az devops` expects it) and `ADO_PROJECT`. Author: `--author` / `EVIDENCE_AUTHOR`, else `git config --global user.name`. Notes folder: `--ws` / `EVIDENCE_WS`, else skipped.

Picking repos: if the user's agent instructions file (AGENTS.md / CLAUDE.md) names default repos or an Azure DevOps org/project, use those; otherwise infer from cwd and git remotes, scan `~/dev` for repos with the user's recent commits, or ask.

Writes `<gh>-prs.json`, `<ado>-ado-prs.json`, `<repo>-commits.txt` (`date hash refs subject`), `transcripts.txt` (folder + date, only with `--ws`) and `MANIFEST.txt`. A real run over about six weeks produced 78 GitHub PRs, 43 ADO PRs, 1252 + 1279 commits and 235 transcript folders in seconds.

Reconcile agents then grep these instead of calling gh/az/git themselves, which keeps 50 parallel units from hammering the APIs and gives every verifier the same frozen facts.

## Why it's built this way (friction mined)

- **`az repos pr list` prints nothing without `--organization` and `--project`.** It silently returns empty. The script always passes both.
- **`gh pr list --author @me --state all --limit 200`** with `--json number,title,state,mergedAt,createdAt,updatedAt,isDraft,url,reviewDecision,baseRefName` is what reconcile needs; `mergedAt` is the proof of done.
- **`git log --all`**, not the current branch: slices live on PR branches and integration branches.
- **Later notes are evidence too.** Meeting transcripts or chat exports prove posts and sends that git never sees; `transcripts.txt` lets a unit pick only folders dated after the commitment.
- **`gh` must be logged in as the right account.** A failed or empty `prs.json` usually means auth: check `gh api user --jq .login`.
- Inline python inside a heredoc broke on quoting; `az --query ... -o tsv | sed` was the fix.

## Related

- `work-overview`: narrative recap from git alone.
- `swarm`: fan reconcile units out over these frozen files.
