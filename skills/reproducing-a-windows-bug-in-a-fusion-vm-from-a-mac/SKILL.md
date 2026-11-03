---
name: reproducing-a-windows-bug-in-a-fusion-vm-from-a-mac
description: "Reproduce Windows-only bugs from a Mac by driving a VMware Fusion Windows 11 VM with vmrun: build the VM with no clicks, bootstrap it, stream results back, verify a published npm package, drive Kiro IDE over CDP via a port forward, and read the agent CLI debug log. Triggers on: reproduce on windows, it only happens on windows, test on windows VM, vmware fusion VM, vmrun runProgramInGuest, build a windows VM, kiro on windows, hooks not firing on windows, windows hook exit code, drive kiro ide, kiro ide over cdp, Processing -File failed because the file does not have a .ps1 extension."
---

## More triggers
windows-vm-repro (old name), test the rc on windows.

repro this on windows, field user is on windows, drive the windows VM, we have 0 visibility, get visibility, reply with pong, set up a windows test box, verify the published beta on windows, smoke the npm package on windows, does the release fix it on windows, VM is stopped, kiro IDE in the VM, remote debugging port in the VM, open a port in the VM, expose cdp to the mac, automate kiro ide, test .kiro/hooks in the IDE, do v2 kiro hooks fire, kiro ide sign in, screenshot kiro ide, self-update on windows, DEP0190 on self-update, isolated npm prefix in the VM, win.sh ps -f, output guard not enforced on windows

# reproducing-a-windows-bug-in-a-fusion-vm-from-a-mac

Run a repro inside a VMware Fusion Windows VM from the Mac terminal (no RDP, no clicking), with output you can see at every step. The worked example is a Kiro hook repro: does a preToolUse "gate" hook that should block a shell command actually block it on Windows?

## Do this

```bash
W=${SKILL_DIR:-~/.claude/skills/reproducing-a-windows-bug-in-a-fusion-vm-from-a-mac}/win.sh
$W create                 # no VM yet: build Win11 arm64 from ~/Downloads/Windows11_Client_arm64_*.iso, no clicks (~10 min)
$W up                     # start the VM if stopped, wait until guest exec answers
$W status                 # VM up? guest exec works? Y: mapped to the mirror?
$W bootstrap              # fresh VM only: roots + VC++ + Node + Git + kiro-cli + framework copy
$W login                  # device-flow kiro-cli login in the VM; the USER allows it in the Mac browser
$W pong my-agent          # visibility gate: version, whoami, agent list, "reply with pong"
$W kiro agent,fix         # scenarios, progress streamed live, then per-hook verdicts
$W verdicts agent         # re-read Kiro's per-hook exit code / timeout / blocked for one scenario
$W ps -c "Get-Process kiro*"   # any ad-hoc PowerShell, output streamed back
```

Inputs (nothing is baked in):
- VM: `WIN_VMX` or `WIN_VM`, else the first VM under `~/Virtual Machines.localized`. Guest user `WIN_GU` (default `winrepro`, password in the keychain, service `reproducing-a-windows-bug-in-a-fusion-vm-from-a-mac`; `create` makes it). Staging: `WIN_SHARE` (default `~/winshare`, copied into the guest at `C:\winshare`, `Y:` in the VM). Elevated user: `WIN_SU` (default the built-in `Administrator`, same password).
- Framework under test: `WIN_SRC`, else the git repo at cwd (copied to `Y:\fw-src`). A published build: `WIN_PKG_SPEC` / `WIN_NPM_REGISTRY` (see below).
- Repro settings (written to `Y:\winrepro\repro.json` on every sync): `WIN_AGENT` (the kiro agent to run with `--agent`; empty = Kiro's default agent), `WIN_INIT_CMD` (installs your framework's `.kiro/` into each fresh probe repo, `{src}` = the framework copy, e.g. `node "{src}\bin\cli.js" init --kiro --force`; empty = copy `<src>\.kiro`), `WIN_GATE_MATCH` (regex that finds the gate hook's command, default `gate|guard`).
- Login: `IDC_URL` / `IDC_REGION` (your IAM Identity Center start URL and region), needed by `login`.
If the user's agent instructions file (AGENTS.md / CLAUDE.md) names defaults for these, use them; otherwise ask.

Verify a **published** release (what field users install), not the checkout:

```bash
$W up && $W pkg @acme/agent-framework@beta        # any npm spec; registry from $WIN_NPM_REGISTRY, else public npm
$W pkg @acme/agent-framework@1.2.0-rc.3           # exact version
WIN_NPM_REGISTRY=<Azure Artifacts npm feed URL> $W pkg @acme/agent-framework@beta   # Azure Artifacts (az token)
WIN_NPM_REGISTRY=https://npm.pkg.github.com $W pkg @<owner>/agent-framework@1.0.0   # GitHub Packages (gh auth)
$W kiro agent                                     # pkg already staged it in Y:\fw-src
```

Kiro scenarios (`ps/kiro-repro.ps1`), each in a fresh git repo with your framework installed plus a capture hook: `agent` (3 shell commands with `--agent $WIN_AGENT`), `nodeversion`, `default` (no `--agent`), `subdir` (run from `src\app`), `hooktimeout` (gate wrapped in an 8 s sleep, 2 s timeout), `hookcrash` (hook exits 1), `exit2` (hook exits 2), `parent` (records the process chain that launched the hook), `fix` (gate + `; exit $LASTEXITCODE`, 30 s timeout). Each one writes `~/winshare/winrepro/out/<s>-run.jsonl` (stream-json), `<s>-kiro.log` (Kiro debug slice), `<s>-capture.jsonl` (every preToolUse payload) and `<s>-agent.json` (the agent config used).

## Visibility rules (users call out "0 visibility")

- **Pong before anything else.** If `$W pong <agent>` doesn't print `pong`, nothing downstream means anything. It also prints `agent list`, which proves the workspace agent loaded.
- **Turn on the CLI's own log.** Kiro: `KIRO_LOG_LEVEL=debug` (set by kiro-repro.ps1), log at `%TEMP%\kiro-log\logs\kiro-chat.log`. Slice it per run by byte offset; `kiro-hook-verdicts.py` turns it into one line per hook: `duration exit_code / Err("command timed out")`, plus `TOOL FAILED/BLOCKED` vs `finished`. That's what proves cause, not the model's self-report. (Its line filter keys on a kiro-cli source location, `agent::agent: 4569`; if a newer kiro-cli prints no HOOK lines, update that string from a fresh log.)
- **Stream, don't batch.** `kiro` tails `out/repro.log` while it runs, and kiro-repro.ps1 echoes each scenario's STEP verdicts and stderr warnings into it. Arm a monitor on that file for long runs.
- **Report what you saw at each milestone.** Don't go quiet during setup.

## Why it's built this way (friction mined)

- **Stage everything in `~/winshare`; the guest gets a copy.** The arm64 VMware Tools has no shared-folder driver (see the Fusion gotchas), so `sync_ps`/`sync_src` tar the staged dirs on the Mac, `copyFileFromHostToGuest` them and unpack into `C:\winshare` (fw-src is wiped first). Installers (`*.msi`, `*.exe`) are left out and copied one by one where they're needed. vmrun runs each guest command in its own logon session, so `gx` maps `Y:` to the mirror (`subst`) on every call, and the ps scripts keep their `Y:\` paths.
- **vmrun returns only the exit code.** `gx` redirects the guest command's stdout+stderr to a file in the mirror and pulls it every 3 s with `copyFileFromGuestToHost`, appending only the new bytes, so output streams with a few seconds' lag. `GX_FOLLOW="a.log b.log"` pulls more files under `out\` the same way (`kiro` follows `repro.log`); `pull_out` copies the whole `out\` back after a run.
- **A `( ... ) > log` group passed through `runProgramInGuest` exits 1 without running**, while plain `a & b > log` works. `gx` writes the command line into a per-call `.cmd` and runs that instead, so a literal `%` must be written `%%` (`ps -c` escapes it for you; `%VAR%` still expands).
- **A fresh Windows can't validate many TLS certs**, so `winget` fails with "Failed when opening source(s)", `Invoke-WebRequest nodejs.org` gets "Could not establish trust relationship", and `kiro-cli login` gets "failed to construct request". Download installers on the Mac, then run `certutil -generateSSTFromWU` and import the roots as SYSTEM (this is what `bootstrap` does).
- **kiro-cli exits `-1073741515` (0xC0000135, DLL not found) with no output on a fresh VM.** It needs the VC++ runtime (`vc_redist.arm64.exe`). Apple Silicon VMs are ARM64, so use the arm64 installers.
- **Run installs as SYSTEM** to avoid UAC: `win.sh sys` copies the script to `C:\Users\Public` (SYSTEM can't see `Y:`) and runs it from a one-shot `schtasks` SYSTEM task (`ps/sys-run.ps1`). The task's `/TR` is a quote-free wrapper `.cmd`: an inline command with embedded quotes fails `Invalid argument/option` under PowerShell 5.1. `/ST is earlier than current time` is a harmless warning.
- **Write JSON from PowerShell 5.1 without a BOM.** `Set-Content -Encoding utf8` adds one, and Kiro then rejects every agent with "expected value at line 1 column 1" and falls back to `kiro_default` ("agent <name> not found"). That looked like a field finding and was our own bug. Use `[IO.File]::WriteAllText(path, text, (New-Object Text.UTF8Encoding $false))`.
- **Quoting through vmrun + cmd + PowerShell is fragile.** Put logic in .ps1/.cjs files under `Y:` and run them with `-File`, and pass settings in a file (`repro.json`). Avoid inline `-Command` with nested quotes, and avoid `node -e` with quotes inside `Start-Process -ArgumentList` (it silently ran different code and gave a false exit 0). Start-Process also doesn't quote array args, so join them with explicit quotes.
- **Kiro IdC region:** the profile name `KiroProfile-us-east-1` does not mean the Identity Center region is us-east-1. Check the real region (set `IDC_REGION`); the wrong region gives `InvalidRequestException`. `login` uses `--use-device-flow` without `--license` (with `--license` and no terminal kiro-cli says "No region was given ... leave out --license"), prints a code and URL, and waits; the user allows it in the Mac browser.
- **The Fusion app can't attach to a VM started by `vmrun start nogui`.** `open -a "VMware Fusion" <vmx>` on the running VM shows nothing. Suspended, the app resumes it in a window, so `show` suspends first (`vmrun start <vmx> gui` on the suspended VM fails with "Cannot connect to the virtual machine"). The "New features are available" dialog on resume is the hardware-version upgrade offer, and the resume waits until the user clicks OK.
- **One run at a time per log.** Two runs writing the same `repro.log` (or a killed run's leftovers) produce confusing timestamps. Kill strays with `$W ps -c "Get-Process kiro-cli* | Stop-Process -Force"`.
- **`kiro-chat.log` restarts per kiro process**, so a byte offset saved before a run can be past the new end, which gives an empty slice. kiro-repro.ps1 resets to 0 when the file shrank.
- **Reading a log mid-write can yield NUL padding.** `win.sh` strips it with `perl -pe 's/\0//g'`, and deletes (not truncates) `repro.log` before a run.
- **Model self-reports are chunked and fuzzy** (`STEP1: ran,` fragments). Trust `verdicts` (Kiro's log) over STEP lines.
- **The VM is often suspended or stopped** between sessions. Run `$W up` first; Windows needs 1 to 3 min after a cold start before guest ops answer.
- **`pong` with no dir warns `failed to set agent '<name>': Internal error`.** Expected: it runs from `%USERPROFILE%`, which has no `.kiro/agents`. It still answers `pong`; pass a repo dir to test the workspace agent.
- **Check the version `pkg` prints.** Dist-tags move under you (another session can cut a new prerelease minutes after yours), so report the exact version you verified, not "beta". Release channels can change what a dist-tag carries (e.g. `@beta` shipping `-rc.N` builds), so check.
- **`pkg` with an Azure Artifacts registry** uses an `az account get-access-token` token in a temp userconfig (deleted after the pack; `~/.npmrc` untouched), so it needs `az login`, not GitHub auth. GitHub Packages uses `gh auth token`; anything else uses `NPM_TOKEN` or your own `~/.npmrc`. The tarball has no node_modules, so `pkg` installs prod deps (Bun, then pnpm, then npm) before syncing.
- **A leftover global install of the same CLI under an old package name owns its `.cmd` shim**, so a global install from the new package fails `EEXIST`. Uninstall the old package first: `npm uninstall -g <old-package>`.
- **Parallel runs skew timing.** Windows hooks are slow (PowerShell + Node cold start is 3.5 to 5.6 s), so a second VM workload pushes them over timeouts.
- **`Y:\fw-src` is shared across sessions.** Another session's `pkg` once swapped it to an older rc while a newer smoke was running, and the CLI reported the wrong version. For a version smoke, stage a private copy (`~/winshare/<tag>/src`, packed the same way `pkg` does), print `cli --version` inside the script, and leave the VM running when someone else is using it.
- **Check CI first.** If CI already smokes setup on Windows against the published package (a setup-smoke workflow), read that run before booting the VM; use the VM when you need a repro or Kiro.
- **Tests written on the Mac break on Windows CI**: hard-coded `/` separators, `\n` vs `\r\n` in output asserts, and `HOME` (Windows uses `USERPROFILE`). Use `path.join`, split on `/\r?\n/`, and `os.homedir()`.
- **The install ISO** (`~/Downloads/Windows11_Client_arm64_*.iso`, about 8 GB): `create.sh` removes the CD drives from the .vmx after setup, so the ISO can be deleted once `create` prints `ready:`.
- **Clean up after testing:** `$W down` suspends the VM so it doesn't hold RAM and battery.

## VMware Fusion gotchas (Fusion 26H1, Win11 arm64 build, 2026-11)

- **A hand-written .vmx needs PCIe root ports.** Without `pciBridge4..7` (`virtualDev = "pcieRootPort"`, `functions = "8"`) `vmrun start` fails with only `Error: The operation was canceled`; vmware.log says `[msg.pci.noslotavail] No PCIe slot available for Ethernet0`. `fusion/create.sh` writes them.
- **Read vmware.log, not the vmrun error.** It sits next to the .vmx and holds the real reason; its timestamps are UTC.
- **Don't kill Fusion's first launch.** It runs its own root installer for its helpers; killing it left an empty, root-owned app. Remount the dmg and run it again.
- **Browser downloads leave `(1)` copies** of the 8 GB ISO; `create.sh` skips names ending ` (N).iso`. Compare with `cmp -s` before deleting one.
- **No Tools, no vmrun.** Every guest op (`runProgramInGuest`, `fileExistsInGuest`) blocks and then logs `VIX_E_TOOLS_NOT_RUNNING`. Until Tools is up, drive the guest by keyboard and screen through `vmcli <vmx> mks`:
  - `sendKeySequence 'text'` types the text literally. `<enter>`, `<win>` and other `<names>` are typed as characters too. A literal newline (`$'\n'` in bash) is Enter.
  - `sendKeyEvent <hid> <modifier>` sends USB HID codes: `0x29 0` is Escape, `0x06 0x01` is Ctrl+C, and the GUI modifier `0x08` opens Start with search focused. `0x28` (Enter) was ignored, so use the newline instead.
  - Type one short command per call. Lines of about 150 characters drop and reorder keystrokes.
  - Wait about 5 s after typing into Start search before Enter, or Enter fires before results exist.
  - `captureScreenshot <png>` grabs the screen; a black frame is often just display sleep, so send `<shift>` and capture again.
- **The guest user name must differ from the computer name.** `net user <name> /add` fails with `The user name may not be same as computer name` (NET HELPMSG 2253), and an unattend LocalAccount with that name silently isn't created or isn't an admin; the next step then says `System error 1317 ... The specified account does not exist`. Three builds went to this before the log showed it. `create.sh` names the computer `<VM name>-VM`.
- **`create.sh` does the account work as SYSTEM**: specialize copies `SetupComplete.cmd` + `firstlogon.ps1` from the unattend disc, and SetupComplete creates the user, adds it to Administrators, installs Tools, logs every exit code to `C:\Users\Public\firstlogon.log`, then deletes itself (it holds the password). The unattend has no UserAccounts block, only AutoLogon.
- **Keep a fallback login.** SetupComplete also enables the built-in Administrator with the same keychain password (test VM only), and `create.sh` pulls `firstlogon.log` as Administrator while it waits (`out/firstlogon.log`, summarized in `create.log`). Without it a failed account leaves no way in: the log is in the guest, and there is no shared folder.
- **Never boot the install ISO again to debug** while the unattend disc is attached: it starts a fresh unattended install and wipes the disk, log included.
- **vmrun's token for the guest user is UAC-filtered.** Even with the user in Administrators, guest ops run at `Medium Mandatory Level` with Administrators as `Group used for deny only`, and `net session` exits 2, so `schtasks /RU SYSTEM` fails. `pss` (`win.sh sys`) therefore runs as the built-in Administrator (`WIN_SU`), whose token is not filtered.
- **The arm64 Tools silent install has no shared folders.** No `vmhgfs` service, no hgfs network provider, and `\\vmware-host\Shared Folders` answers `The specified network name is no longer available`. Rerunning `setup.exe` from a guest op (`/S /v"/qn ADDLOCAL=ALL"`, or `/a` to extract the MSI) hung in session 0 with no MSI log, twice, so the skill copies files instead of fixing HGFS.
- **Check admin with `whoami /groups`, not the account list.** A standard user shows `Medium Mandatory Level` and no BUILTIN\Administrators; `net session` exits 1. vmrun guest ops still work for that user, so they don't prove admin.
- **A guest op can hang for minutes** right after the Tools install (`runProgramInGuest ... cmd /c ver` sat 8 min while `exit 3` returned at once). Bound every vmrun call (`perl -e 'alarm 60; exec @ARGV' vmrun ...`).
- **The "Press any key to boot from CD" prompt** is passed by any keystroke, so typing during the first 20 s of boot is enough.

## Self-update and version smoke without touching the VM's real global install

Stage a private copy and script under `~/winshare/<dir>`, `$W push <dir>`, then run it with `$W ps -c "powershell -NoProfile -ExecutionPolicy Bypass -File Y:\\<dir>\\smoke.ps1"`. There is no `ps -f`: `$W ps -f x.ps1` fails with `Processing -File 'Y:\winrepro\-f' failed because the file does not have a '.ps1' extension`.

For self-update A/B (vN vs vN+1), in the .ps1: set `NPM_CONFIG_PREFIX` and `NPM_CONFIG_USERCONFIG` to a temp dir, prepend the prefix to PATH, `npm i -g <package>@<old>`, run `<prefix>\\<cli>.cmd self-update *> su.log`, count `DEP0190` (Node's warning for `spawn` with `shell: true` and an args array), then run self-update again (now the new code) and count again. Write the registry token npmrc into the staged dir from the Mac (`umask 077`) and push it; the script copies it into the VM temp dir and deletes the `Y:` copy and the temp copy, and you delete the Mac copy. A fixed build prints 0 `DEP0190`.

## Kiro IDE over CDP (the GUI, not kiro-cli)

```bash
$W ide install                         # latest Kiro IDE from kiro.dev/downloads, downloaded on the Mac, signature-checked, silent user install
$W ide up 'C:\Users\Public\kiro-ide-ws' # (re)launch with CDP on 127.0.0.1:9222, forward <VM-IP>:9223 -> it, firewall = Mac only
$W ide targets                         # page (workbench) + iframe extensionId=kiro.kiroAgent (chat)
$W ide text [main|chat]                # visible text incl. shadow roots
$W ide click "Sign in"                 # first button/link with that exact label, main then chat
$W ide send '<prompt>'                 # type into the chat (ProseMirror) with trusted CDP key input + Enter
$W ps ide-trust.ps1                    # test VM only: security.workspace.trust.enabled=false (no Restricted Mode)
$W ps marker.ps1 -Dir 'C:\\...\\ws'      # FIRED/absent for a test hook that writes .hook-fired (-Name to change)
$W ide shot [file.png]                 # workbench screenshot (default ~/winshare/winrepro/out/ide.png); read it to see the screen
$W ide eval '<js>' | evalmain '<js>'   # raw JS in chat webview / workbench
```

A VM started by `vmrun`/`win.sh up` runs **windowless** (no Fusion window), so the user sees nothing: run `$W show` (suspends, then resumes in a Fusion window) before any step that needs them in the VM. First run: `ide click "Sign in"` opens the VM's browser at app.kiro.dev with `redirect_uri=localhost:3128` **inside the VM**, so the USER finishes the login there (`IDC_URL` start URL, region `IDC_REGION`). A new workspace opens in Restricted Mode; run `ps ide-trust.ps1` once so no workspace opens restricted.

Friction mined (Kiro IDE 1.2.4 win32-arm64, Electron 44):
- **Chromium binds the debug port to 127.0.0.1 only** (`--remote-debugging-address` is ignored outside headless). Expose it with `netsh interface portproxy` (needs the `iphlpsvc` service running) plus a firewall rule scoped to the Mac's address on the VM network, as SYSTEM (`ide-port.ps1`; win.sh passes the Mac address). Never open it to any address: CDP is full remote code execution.
- **The VM's IP:** `vmrun getGuestIPAddress` (needs Tools). The Mac side is the `.1` of the Fusion NAT subnet (`vmnet8`); `ide-port.ps1` finds the guest address from its default route.
- **Launch through `schtasks /IT`** so Kiro lands on the interactive desktop (session 1); `ide-launch.ps1` polls `/json/version` for 30 s. It kills any running Kiro first, so do not `ide up` mid-sign-in.
- **Kiro renders whole screens (sign-in) inside shadow roots.** `document.body.innerText` and `querySelector` miss them, and a naive `shadowRoot.textContent` dumps Tailwind CSS. `kcdp.mjs` walks shadow roots and skips STYLE/SCRIPT.
- **The chat is a webview iframe target whose UI sits in a nested frame.** Only execution contexts that render text are the real UI; `kcdp.mjs` filters to those.
- **`.kiro/hooks/*.json` is read by Kiro IDE only.** kiro-cli 2.26.1 ignores that folder entirely; its hooks come from the `hooks` block in `.kiro/agents/*.json` (that's why an agent-level gate fires in kiro-cli). Proving a `.kiro/hooks` change needs the IDE path, not `win.sh kiro`.
- **v2 `<id>.json` (top-level `hooks` array) is the IDE's current format**: the IDE's kiroAgent extension has `kiroAgent.hooks.migrateToV2`.
- **Sending a prompt:** no public `kiroAgent.*` command takes prompt text. The input is `.chat-input-content` (tiptap/ProseMirror) in the chat webview; focus it, then CDP `Input.insertText` + `Input.dispatchKeyEvent` Enter (synthetic DOM events don't drive ProseMirror). `ide send` does this; give the agent ~25-60 s, then `ide text chat`.
- **After sign-in, the next launch shows a full-screen onboarding ("Import configuration")** and the chat panel doesn't load, so `send` says `chat input not found`. `ide click "Skip All"` clears it. Always `ide shot` and look at the PNG when a step fails: the DOM text alone hid this.
- **Sign-in times out** if the user isn't watching (the VM was windowless): `ide click "Cancel"` (if shown) then `ide click "Sign in"` gives a fresh `state=`; tell the user to use the tab whose URL has that state.
- **Guest exec can hang indefinitely** (seen on the VM-IP lookup). `ide` caches the IP in `out/.vm-ip` (override `WIN_IP`) and bounds the lookup with `perl -e 'alarm 20; exec ...'`; macOS has no `timeout`.
- **Proven:** a v2 `PreToolUse` hook in `.kiro/hooks/` fires in Kiro IDE on a Read File tool call; the same workspace without the file does not.

## Kiro hook findings this skill reproduces (kiro-cli 2.26.1, Win11 ARM)

| Case | Kiro log verdict | Result |
|---|---|---|
| Installed gate `node <gate-script>` (timeout 5000) | `exit_code: 1` (3/3) | all 3 raw commands ran |
| Gate under load | `Err("command timed out after 5000 ms")` | command ran (timeouts fail open) |
| `<gate>; exit $LASTEXITCODE`, timeout 30000 | `exit_code: 2` (3/3, one took 5.62 s) | 3/3 blocked; also blocks on macOS |
| Published fixed build (`$W pkg`), fresh install | `exit_code: 2` (3/3, 2.5 to 3.3 s) | 3/3 blocked |

Release-cut gotchas seen while shipping that fix:
- Pushing two tags back to back queues both publish runs in one concurrency group; the rc run came back `cancelled`. Check `gh run list --workflow "<publish workflow>"` and `gh run rerun <id>` (the tag still matches package.json), then confirm with `npm view <pkg> dist-tags --registry <registry>`.
- A test that passes in CI can fail only in your main worktree because gitignored local installs (`.opencode/`, `.claude/`) leak config into it. Confirm in a clean `git worktree add` of the same commit before treating it as a release blocker.

In plain words: Kiro on Windows runs each hook as `powershell -Command "<hook>"`. Windows PowerShell turns the hook's "block" exit code 2 into a generic 1, and Kiro treats 1 as "just a warning", so the command runs anyway. Adding `; exit $LASTEXITCODE` passes the real code through. On macOS/Linux `sh` reads it as a bare `exit`, which keeps the last command's code, so one string works everywhere.

## Related

- `forge-skill-from-session-friction`: harden this skill the same way when a new Windows gotcha bites.
- `scrub-and-open-issue`: file the upstream Kiro issue (hook exit code via `powershell -Command`) without PII.
- `measuring-what-a-kiro-agent-loads-into-context`: what Kiro actually loads into context, on any OS.
- `diffing-web-app-aria-snapshots-a-vs-b`: the same CDP driving, for web apps instead of the IDE.
