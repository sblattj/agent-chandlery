---
name: scrub-and-open-issue
description: 'Scrub PII, company and internal identifiers from a GitHub issue draft, then file it via gh as the target repo''s OWNER account (your personal account), never your work account; hard gate, no issue if gh cannot act as owner. Triggers on: "open a scrubbed issue", "file a sanitized bug/feature", "open an issue but scrub PII", "file this as the repo owner not my company account", "redact company info and open an issue", "report this upstream without leaking work stuff", "pii scrub please", "anonymize the speaker table".'
---

## More triggers

working inside a company/org repo and hit a limitation of a tool or framework you want to report upstream; "open an anonymous issue on <owner/repo>"; "post replay evidence on the issue"; push or open a PR on a personal repo as its owner.

# Scrub PII and open a GitHub issue as the repo owner

Use this when you are working inside a company/org repo (for example `my-org/acme-api`) and want to file a bug or feature request against a **separate** tool/framework repo (typically one the user owns under their personal account, `<owner>` below) without leaking any employer, teammate, product, or personal identifiers, and without the company GitHub account (whatever login is on the local blocked-authors list) authoring it.

The idea: two GitHub accounts live side by side in `gh` (a personal one that owns your tools, a work one that is usually active). Anything filed, commented or pushed on a personal repo goes out as the personal owner, scrubbed of work details, and the work account never authors it.

## The two hard rules (do not skip)

1. **Author = repo owner, or no issue.** The gh account that creates the issue MUST equal the target repo's owner (for user-owned repos). If gh is not authenticated as that owner, or the only usable account is a blocked/company account, DO NOT create the issue. Stop and tell the user.
2. **Nothing internal leaks.** The final title and body carry zero employer names, product names, teammate names, the user's own name, emails, internal repo/branch/ticket IDs, internal paths, internal URLs/hostnames, or secrets. Describe the problem abstractly.

## Inputs you need

- **Target repo** as `owner/repo` (the repo you file against). Ask if not given. It is almost never the current company repo.
- **What to report**: the bug or the feature, drafted from the current context. You write it; the user does not have to.

## Steps

### 1. Draft generic
Write a title (one line) and a Markdown body describing the bug or feature in tool-neutral terms. Frame it as a general capability gap, for example "a framework that orchestrates SDLC agents lacks X", not "our acme-api SDLC flow can't do X". No business specifics, no proprietary logic.

Save them:
```bash
D=$(mktemp -d)
printf '%s\n' "TITLE HERE" > "$D/title.txt"
cat > "$D/body.md" <<'EOF'
BODY HERE
EOF
```

### 2. Scrub, then lint until clean
Rewrite the draft to strip anything internal. Categories to remove:
- Personal: the user's own name, any teammate names, emails, GitHub logins of colleagues.
- Employer / product: the employer, parent company, org, product and platform names (the local blocklist has the literal list), and any other brand.
- Internal systems: internal repo names, branch names, ADO/Jira/PBI/work-item numbers, ADO org/project, internal hostnames and URLs, service names.
- Machine: home paths (`$HOME/...` spelled out), worktree paths (anything under your worktree root), scratch and temp paths.
- Secrets: tokens, keys, passwords (obviously).
- Screenshots: only attach if UI chrome shows nothing identifying. Prefer text.

Then run the linter and fix every hit. Re-run until it exits clean:
```bash
python3 ${SKILL_DIR:-~/.claude/skills/scrub-and-open-issue}/scripts/leak_lint.py "$D/title.txt" "$D/body.md"
```
A hit is a line + label + the matched text. Reword to remove it (the linter is intentionally aggressive; some hits are false positives you can confirm are harmless, but every real identifier must go). Terms come from two files. `reference/denylist.txt` holds generic, shareable patterns (ticket-id shapes). Employer, teammate and internal-repo terms live in the local-only blocklist `~/.config/scrub/blocklist.txt` (override with `$SCRUB_BLOCKLIST`), one term or `re:regex` per line. That file is never committed anywhere, dotfiles included. Add new terms there when the user names more things to scrub. If it is missing the linter warns and runs only the built-in and generic checks, so create it before trusting a clean result.

### 3. Confirm the author gate (dry run)
```bash
${SKILL_DIR:-~/.claude/skills/scrub-and-open-issue}/scripts/open_issue.sh \
  --repo OWNER/REPO --title-file "$D/title.txt" --body-file "$D/body.md" --check-only
```
This resolves the owner, checks gh has that account, and reports who would author. If it refuses, stop and relay the reason. Do not work around it.

### 4. Show the user, get explicit approval
Filing an issue is outward-facing. Print the final scrubbed **title**, **body**, **target repo**, and **resolved author login**, and ask the user to approve before you create it. Wait for a yes.

### 5. Create it
```bash
${SKILL_DIR:-~/.claude/skills/scrub-and-open-issue}/scripts/open_issue.sh \
  --repo OWNER/REPO --title-file "$D/title.txt" --body-file "$D/body.md" [--label bug]
```
Report the returned issue URL and the authoring account. Clean up `$D`.

## Batch mode (several issues at once)
Use this when filing a set of findings, e.g. several gaps found in one review, or a batch of friction items from a replay.
- Write one `$D/<n>/title.txt` and `body.md` per issue. Lint them all in one loop, and don't file anything until every one is clean.
- Run `--check-only` once (same repo, same author). Then show the user a numbered title list plus one sample body, and get one approval for the whole batch.
- File them in order, and print `n -> URL` for each. If one fails, stop and report it; don't skip ahead.
- Check for duplicates first with `gh issue list --repo R --search "<keywords>" --state all`.

## Closing with evidence
When a fix ships, close each issue with a comment naming the release, the commit, and the proof (a test name, a replay run, or a before/after excerpt). Run the comment through `leak_lint.py` first, the same way as the issue. Leave an issue open if its proof is partial, and say why in a comment.

## Comments follow the same author rule
A plain `gh issue comment` posts as the **active** account, which is usually the company one. A comment once went out under the work account that way and had to be deleted and reposted. Always comment with:
```bash
python3 ${SKILL_DIR:-~/.claude/skills/scrub-and-open-issue}/scripts/leak_lint.py "$D/comment.md" && \
GH_TOKEN=$(gh auth token --user OWNER) gh issue comment N --repo OWNER/REPO --body-file "$D/comment.md"
gh api repos/OWNER/REPO/issues/N/comments --jq '.[-1].user.login'   # must print OWNER
```

## Pushes and PRs follow the same author rule
A plain `git push` to a personal repo goes out under whatever credential git finds, which is usually the company one (a push to a personal repo once got a 403 because the active gh account was the work account; had it been allowed, it would have gone out under the wrong identity). Never push or open a PR on a personal repo with raw `git push` / `gh pr create`. Use:
```bash
S=${SKILL_DIR:-~/.claude/skills/scrub-and-open-issue}/scripts/push_as_owner.sh
$S check                                   # who would act; refuses blocked owners and org repos
$S push                                    # current branch, -u, as the repo owner
$S push mybranch:main                      # fast-forward main (the "merge" for personal repos)
$S pr --title "T" --body-file body.md      # PR as the owner (head = current branch, base = default)
```
`push` also refuses if a commit about to go up has an author/committer email matching the local-only `~/.config/scrub/blocked-email-domains.txt` (override `$SCRUB_BLOCKED_EMAILS`; missing file = warning, check skipped), or the refspec fails `leak_lint.py`; `pr` lints title, head and body. The token is scoped to that one git/gh call via the environment and the active account is untouched. `--check-only` on `push`/`pr` runs every gate without acting.

## Commit identity in personal repos
Set it up once so any checkout with a personal remote commits as the personal account. In `~/.gitconfig`:
```ini
[includeIf "hasconfig:remote.*.url:https://github.com/<owner>/**"]
    path = ~/.gitconfig-personal
```
plus the same block for the ssh remote form (`hasconfig:remote.*.url:` followed by the ssh URL prefix of `<owner>/**`). Then
`~/.gitconfig-personal` sets `user.name = <owner>`, `user.email = <id>+<owner>@users.noreply.github.com` (the noreply address from your GitHub email settings). A repo-local `user.*` would override it, so never set one in those repos.

`scripts/identity-guard.sh` enforces it:
```bash
G=${SKILL_DIR:-~/.claude/skills/scrub-and-open-issue}/scripts/identity-guard.sh
$G --owner <owner> --email '<id>+<owner>@users.noreply.github.com' --ours '<owner>|<first>|<last>' --check   # report only
$G --owner <owner> --email '<id>+<owner>@users.noreply.github.com' --ours '<owner>|<first>|<last>'           # fix
```
For every checkout under `--roots` (default `~/dev ~/code ~/.wt`) whose origin is `github.com/<owner>/...`, it clears repo-local identities, writes the expected identity as `identity-guard.*` config keys, and symlinks `scripts/hooks/pre-commit` and `pre-push` into the common git dir (shared by all worktrees). An existing non-guard hook is left alone and reported. pre-commit refuses an author or committer that isn't `<owner> <email>`; pre-push refuses new commits whose name or email matches `--ours` (your name parts, so a commit made under the work identity is caught) but isn't the expected identity (`IDENTITY_GUARD_PUSH_ALLOW=1` for a reviewed rewrite). Run it after cloning a new personal repo. Pushes go through `push_as_owner.sh` above, which refuses company-domain commits too if the hooks were bypassed.

## Org-owned targets
A GitHub issue cannot be authored "as an organization." If the target repo owner is an org, the script refuses unless you pass `--author <login>` naming a specific authenticated, non-blocked account to file as. Confirm that choice with the user first; never default an org target to the company account.

## Anonymizing data tables (speaker names, meetings)
Evidence tables from real data (transcripts, replays) leak through the data itself, and the linter's denylist doesn't know teammate names.
- Map consistently across every comment on the issue: meetings `M1..Mn`, people `Speaker A..E`. Unmapped values sneak in from new fields: a registry voice that appeared only as a `runner_up` value leaked into a draft until it was mapped to `Speaker F`/`G`. Build the table with a script that has the map, and default unknown names to a new letter, never the raw value.
- After the linter, grep the final file for every real name in the dataset (`grep -cE "First1|First2|..." comment.md` must print 0).
- Descriptions are PII too. A roster description by accent and gender was pulled after the user said "pii scrub please" mid-turn. Describe the property ("several near-identical same-accent voices"), not the people.
- Don't state a fact you only inferred (e.g. "in both blends a second placed voice..."). Check the data first, or soften it to what was observed.

## Notes
- The script never switches your active gh account. It uses `gh auth token --user <login>` to file under one account for that single command only.
- Blocked authoring accounts (never allowed to file, push or open PRs) are read from `reference/blocked-authors.txt` (shareable, usually empty) plus the local-only `~/.config/scrub/blocked-authors.txt` (override `$SCRUB_BLOCKED_AUTHORS`), which holds the work account. If the local file is missing the scripts warn and only the owner gate applies.
- Local-only files under `~/.config/scrub/` (`blocklist.txt`, `blocked-authors.txt`, `blocked-email-domains.txt`) carry the employer-specific literals. Never copy their contents into this skill or any repo.
