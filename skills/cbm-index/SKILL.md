---
name: cbm-index
description: "Index a repo into codebase-memory-mcp the right way: survey the tree, write a fitted .cbmignore, then run index_repository with mode=full (never default to fast). Triggers on: index this repo, cbm index, codebase-memory index, reindex with cbmignore, write a .cbmignore, index a directory of repos, the index is missing docs/skills/commands, why did fast mode skip files, cbm cache too big, delete orphaned or audit indexes."
---

# cbm-index: fitted .cbmignore + full index

`fast`/`moderate` modes silently add skip dirs (`docs`, `examples`, `testdata`, `.claude`, `scripts`, `bin`, ...) and filename filters (tests, `.d.ts`, lockfiles, `.min.js`). For prompt-pack, plugin, and docs-heavy repos that is the payload. Default to **full** and control noise with `.cbmignore` instead.

## Workflow

1. **Survey** the repo before deciding anything:
   ```bash
   ${SKILL_DIR:-~/.claude/skills/cbm-index}/scripts/survey.sh <repo> [top-n]
   ```
   Read: top-level and second-level hotspots, extension mix, noise candidates, files >300K, duplicated mirror trees, existing `.gitignore`/`.cbmignore`.

2. **Decide excludes** with this rule of thumb. When unsure, keep it; a full index of extra markdown is cheap, a missing skill file is not.

   | Exclude | Keep |
   |---|---|
   | Build output, compiled bundles (`dist/`, `web-bundles/`, `public/` built assets) | Source, including `scripts/`, `bin/`, `tools/` |
   | Test fixtures, snapshots, test models, regression corpora | Test source files |
   | Vendored / third-party / generated code, `.patch`, `.xsd`, `.wsdl` | Hand-written configs (yaml/json/toml) |
   | Media, icons, fonts (already suffix-filtered, list only if a dir is pure media) | `docs/**/*.md`, ADRs, blog posts if they explain the system |
   | Lockfiles, `.map`, `.min.*`, large data (`csv`, `pkl`, `ipynb`, >1MB json blobs) | `.claude/`, `.agents/`, `skills/`, `commands/`, `plugins/` content |
   | Duplicated mirror trees (e.g. `.cursor-plugin/` copy of `plugins/`) | The canonical copy |
   | `.changeset/`, CHANGELOG fragments | README, CONTRIBUTING, architecture docs |

3. **Write `<repo>/.cbmignore`** (root only, nested files are ignored). Start with a header comment naming the repo and date. Gitignore syntax; see cheatsheet below.

   **Always add `!.claude/`** when the repo ships Claude agents/commands/skills. `.claude/` is on the built-in skip list even in full mode; only a `.cbmignore` negation brings it back. Verified on two public agent-framework repos (+18k and +10k nodes). Same trick for other skipped dot-dirs that carry payload (`.agents/`, `.cursor/`) if `excluded.dirs` shows them.

   If the repo isn't yours, keep `git status` clean:
   ```bash
   grep -qx '.cbmignore' <repo>/.git/info/exclude 2>/dev/null || echo '.cbmignore' >> <repo>/.git/info/exclude
   ```

4. **Index with full mode.** MCP tool `mcp__codebase-memory-mcp__index_repository` with `mode: "full"`, or from a shell:
   ```bash
   codebase-memory-mcp cli --progress index_repository --repo-path <repo> --mode full
   ```
   Fall back to `moderate` only if full fails on memory/time for a huge monorepo, and say so. Never `fast` for repos whose value is in markdown/yaml.

5. **Verify the response**, don't just read `status: indexed`:
   - `excluded.dirs` should list only what you meant. If a wanted dir shows up (e.g. `docs`), you're not in full mode or a `.gitignore` rule hit it.
   - `skipped_count` > 0 means files not indexed at all (oversized/parse failures). Open the `logfile` to see which.
   - `parse_partial` ranges: usually docker/nginx/helm templates. Fine unless it's real source.
   - `status: degraded` means persisted nodes fell short. Reindex.
   - Sanity-check node count against `git ls-files | wc -l`. A 5k-file repo yielding 500 nodes means the payload got skipped.
   - Spot-check with `check_index_coverage(project, scopes=["docs", "skills", ...])` on the dirs you care about.

6. **Iterate**: if noise leaked (thousands of nodes from `public/` or `fixtures/`), tighten `.cbmignore` and reindex. Changes take effect on the next index.

## Gotchas

- Index refused with "pre-coordination or unverified CBM generation is active": the coordinator is wedged by orphaned marker files in its /tmp coordination dir, and a daemon restart doesn't clear them (only a reboot did). Run `${SKILL_DIR:-~/.claude/skills/cbm-index}/scripts/cbm-unwedge.sh --dry-run` to see the markers, then `cbm-unwedge.sh --reindex <repo...>` (stops the permanent daemon, backs up and clears the coordination dir, respawns, reindexes full, sequentially). Index DBs are never touched. Still happened on 0.11.0.
- Updating cbm: `install.sh` exits 1 when it won't rewrite `~/.codex/config.toml` or OpenCode agent files, but the binary still updates. Check `codebase-memory-mcp --version` before retrying. Running sessions keep the old server (MCP shows CONNECTION_CLOSED); restart them.
- Throwaway indexes (one-off audits, scratch clones, replay sandboxes, PR worktrees): `delete_project` them as soon as the task's answer is written. One repo audit indexed every checkout as its own project and left 570 `audit-*` indexes (26 GB of a 35 GB cache) after the checkouts were deleted. Sweep: `list_projects`, and any project whose `root_path` no longer exists is an orphan; delete it (or `rm ~/.cache/codebase-memory-mcp/<name>.db` with no server writing).
- Index worktrees of the same repo separately (a second worktree on trunk next to the main checkout on a feature branch), each with its own git-excluded `.cbmignore`.

## .cbmignore cheatsheet

- One pattern per line, `#` comments. `*` and `?` don't cross `/`; `**` does.
- Trailing `/` = directories only. Leading `/` anchors to repo root. No `/` = match name at any depth.
- `!pattern` re-includes; last match wins. Can un-skip built-in skip dirs like `docs/` or `target/` (not `.git`, `node_modules`, `.worktrees`, `.claude-worktrees`).
- Cannot rescue a file whose parent dir is excluded. Negate the dir instead.
- Cannot override built-in suffix filters (`.png`, `.o`, `.db`), fast-mode filename filters, or the max-file-size cap.
- Precedence: built-in skip list, repo `.gitignore` + `info/exclude`, nested `.gitignore`, `.cbmignore`, git global excludes.

Reference: https://github.com/DeusData/codebase-memory-mcp/blob/main/docs/cbmignore.md

## Template

```gitignore
# .cbmignore for <repo> (cbm-index, <date>)
# rescue built-in skip dir that holds agent/command payload
!.claude/
# build output / bundles
dist/
build/
web-bundles/
/dashboard/public/
# test data
**/fixtures/**
**/__snapshots__/**
**/test-models/**
# generated / vendored
*.patch
*.xsd
*.min.js
*.min.css
*.map
*.lock
package-lock.json
# large data
*.pkl
*.ipynb
*.csv
# release noise
.changeset/
```

## Batch mode

For many repos (e.g. everything under one parent directory): run survey.sh on each in one shell call, write every `.cbmignore` in one call, then fire all `index_repository(mode="full")` calls in a single message. Report per repo: nodes, edges, excluded count, skipped, parse_partial, and anything you deliberately left out.
