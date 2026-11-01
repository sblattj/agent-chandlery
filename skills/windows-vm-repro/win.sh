#!/usr/bin/env bash
# Drive a VMware Fusion Windows VM from the Mac for bug repros, with visible output.
# Usage: win.sh <cmd> [args]   (VM = $WIN_VMX, else $WIN_VM's .vmx, else the first VM under ~/Virtual Machines.localized)
#   create [iso]                build a Windows 11 arm64 VM with no clicks (fusion/create.sh), then bootstrap it
#   status                      VM state + guest exec reachability + Y: mapping
#   show                        open the VM's window on the Mac (a VM started by vmrun/up runs windowless)
#   up                          start the VM if stopped and wait (<=5 min) until guest exec answers
#   down                        suspend the VM (frees its RAM)
#   pkg [spec]                  stage a PUBLISHED package instead of the checkout: npm pack <spec> (or $WIN_PKG_SPEC)
#                               from $WIN_NPM_REGISTRY (else public npm). Auth by registry host: Azure Artifacts
#                               (Azure DevOps pkgs host) -> az token, GitHub Packages -> gh token, else your ~/.npmrc.
#                               Installs prod deps, syncs to Y:\fw-src. Then: win.sh kiro agent
#   bootstrap                   fresh-VM fixes: roots, VC++ runtime, Node, Git (downloaded on the Mac), kiro-cli, framework copy
#   ps <file.ps1|-c "cmd"> ...  run a PowerShell script from the share (or inline) as the guest user, output streamed here
#   sys <file.ps1> ...          same, as SYSTEM (installs without UAC; file is copied to C:\Users\Public first, run by sys-run.ps1)
#   login                       kiro-cli device-flow login in the VM; the user allows it in the Mac browser
#   pong [agent] [dir]          visibility smoke: version, whoami, agent list, "reply with pong"
#   kiro <scenarios> [src]      Kiro hook repro scenarios (agent,nodeversion,default,subdir,hooktimeout,hookcrash,exit2,parent,fix); progress log streamed
#   verdicts <scenario>         per-hook exit code / timeout / blocked from Kiro's debug log slice
#   ide install                 download the latest Kiro IDE (win32-arm64|x64) on the Mac, signature-check + silent-install as the user
#   ide up [C:\path\to\ws]        (re)launch Kiro IDE on the desktop with CDP 127.0.0.1:9222, expose it as <VM-IP>:9223 to the Mac only
#   ide <targets|text|click|send|eval|evalmain|shot> [arg]   drive the IDE via kcdp.mjs (see that file); shot defaults to $OUT/ide.png
#   sync [src]                  re-copy ps assets + framework checkout (default $WIN_SRC, else the git repo at cwd) to the guest mirror
#   push <dir>                  copy ~/winshare/<dir> (installers excluded) into the guest mirror as Y:\<dir>
# Env: WIN_VMX | WIN_VM, WIN_GU (guest admin, default winrepro; password: WIN_GP, else keychain service windows-vm-repro),
#      WIN_SHARE (~/winshare, mirrored into the guest at C:\winshare and mapped as Y: on every call), WIN_SU (elevated guest user, Administrator), WIN_SRC, WIN_PKG_SPEC, WIN_NPM_REGISTRY,
#      IDC_URL + IDC_REGION (your IAM Identity Center start URL and region; required for `login`),
#      WIN_AGENT (kiro agent to test), WIN_INIT_CMD (installs .kiro into a probe repo; {src} = framework copy),
#      WIN_GATE_MATCH (regex for the gate hook command), WIN_IP (skip the VM IP lookup)
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); LIB="/Applications/VMware Fusion.app/Contents/Library"
VMRUN="$LIB/vmrun"; VMCLI="$LIB/vmcli"; VMS="$HOME/Virtual Machines.localized"
VMX=${WIN_VMX:-$( [ -n "${WIN_VM:-}" ] && echo "$VMS/$WIN_VM.vmwarevm/$WIN_VM.vmx" || ls "$VMS"/*.vmwarevm/*.vmx 2>/dev/null | head -1)}
VM=$(basename "${VMX:-none}" .vmx); GU=${WIN_GU:-winrepro}
GP=${WIN_GP:-$(security find-generic-password -s windows-vm-repro -a "$GU" -w 2>/dev/null)}
SHARE=${WIN_SHARE:-$HOME/winshare}; STAGE=$SHARE/winrepro; OUT=$STAGE/out
IDC_URL=${IDC_URL:-}; IDC_REGION=${IDC_REGION:-}
mkdir -p "$OUT"
vr() { "$VMRUN" -T fusion "$@"; }
running() { vr list | grep -qxF "$VMX"; }
# The arm64 VMware Tools has no shared-folder driver, so $SHARE is mirrored into the guest at C:\winshare by copy, and
# every call maps Y: to that mirror (subst). Paths in the ps scripts stay Y:\winrepro, Y:\fw-src.
G='C:\winshare'; GXU=$GU
gop() { perl -e 'alarm 300; exec @ARGV' "$VMRUN" -T fusion -gu "$GXU" -gp "$GP" "$@"; }   # one bounded guest op
# push <dir under $SHARE> [clean]: tar on the Mac, unpack into the mirror (installers excluded: push_file sends those)
push() { local d=$1 t rc; t=$(mktemp -t winpush)
  COPYFILE_DISABLE=1 tar czf "$t" -C "$SHARE" --exclude "$d/out" --exclude '*.msi' --exclude '*.exe' "$d" || { rm -f "$t"; return 1; }
  gop copyFileFromHostToGuest "$VMX" "$t" 'C:\Users\Public\winpush.tgz'; rc=$?; rm -f "$t"; [ $rc = 0 ] || return 1
  gop runProgramInGuest "$VMX" 'C:\Windows\System32\cmd.exe' \
    "/c ${2:+rmdir /s /q $G\\$d 2>nul & }mkdir $G 2>nul & tar -xzf C:\\Users\\Public\\winpush.tgz -C $G & del C:\\Users\\Public\\winpush.tgz"; }
push_file() { gop copyFileFromHostToGuest "$VMX" "$STAGE/$1" "$G\\winrepro\\$1"; }
# pull <guest file> <host file>: append whatever the guest file grew by since the last pull
pull() { local t="$2.pull"; gop copyFileFromGuestToHost "$VMX" "$1" "$t" >/dev/null 2>&1 || return 0
  local n; n=$(wc -c < "$2" 2>/dev/null || echo 0); tail -c +$((n+1)) "$t" >> "$2"; rm -f "$t"; }
sync_ps() { rsync -a "$HERE/ps/" "$STAGE/"   # repro settings go in a file: quoting args through vmrun + PowerShell is fragile
  jq -n --arg agent "${WIN_AGENT:-}" --arg initCmd "${WIN_INIT_CMD:-}" --arg gateMatch "${WIN_GATE_MATCH:-}" \
    '{agent:$agent, initCmd:$initCmd, gateMatch:$gateMatch}' > "$STAGE/repro.json"; push winrepro; }
sync_src() { local src=${1:-${WIN_SRC:-$(git rev-parse --show-toplevel 2>/dev/null)}}
  [ -n "$src" ] && [ -d "$src" ] || { echo "no framework source: pass a source dir, set WIN_SRC, or run from inside the checkout"; exit 1; }
  rsync -a --delete --exclude .git --exclude coverage --exclude evals --exclude .wt --exclude node_modules/.cache "$src/" "$SHARE/fw-src/"
  push fw-src clean && echo "framework $src -> Y:\\fw-src"; }
# gx <cmd.exe command line>: run it in the guest as $GXU. vmrun returns only the exit code, and a "( ... ) > log"
# group dies with exit 1 when passed through it, so the line goes into a per-call .cmd (write a literal % as %%).
# Its stdout+stderr land in the mirror and are pulled every 3 s and printed here (NUL padding stripped). GX_FOLLOW
# names more files under out\ to pull the same way (e.g. repro.log). The .cmd maps Y: first: each vmrun logon starts without it.
gx() { local id="gx-$$-$RANDOM" rc; local f="$OUT/.$id.log" gl="$G\\winrepro\\out\\.$id.log" gc="C:\\Users\\Public\\$id.cmd" x; : > "$f"
  printf '@echo off\r\nsubst Y: %s >nul 2>&1\r\n%s\r\n' "$G" "$*" > "$f.cmd"
  gop copyFileFromHostToGuest "$VMX" "$f.cmd" "$gc" >"$f.vmrun" 2>&1 || { cat "$f.vmrun" >&2; rm -f "$f" "$f.cmd" "$f.vmrun"; return 1; }
  gop runProgramInGuest "$VMX" 'C:\Windows\System32\cmd.exe' "/c mkdir $G\\winrepro\\out 2>nul & $gc > $gl 2>&1" >"$f.vmrun" 2>&1 & local run=$!
  pullall() { pull "$gl" "$f"; for x in ${GX_FOLLOW:-}; do pull "$G\\winrepro\\out\\$x" "$OUT/$x"; done; }
  { while kill -0 "$run" 2>/dev/null; do sleep 3; pullall; done; } & local pp=$!
  { tail -n +1 -f "$f" | perl -pe 'BEGIN{$|=1} s/\0//g; s/\r//g; s/\x1b\[[0-9;]*m//g'; } & local tp=$!
  wait "$run"; rc=$?; wait "$pp"; pullall; sleep 1; pkill -P "$tp" 2>/dev/null; kill "$tp" 2>/dev/null; wait "$tp" 2>/dev/null; wait "$tp" 2>/dev/null
  gop runProgramInGuest "$VMX" 'C:\Windows\System32\cmd.exe' "/c del $gl $gc" >/dev/null 2>&1
  grep -v '^$' "$f.vmrun" | grep -v 'non-zero exit code' >&2; rm -f "$f" "$f.cmd" "$f.vmrun"; return $rc; }
# pull_out: copy the guest's out\ back after a script that writes its own files there
pull_out() { local t; t=$(mktemp -t winout)
  gop runProgramInGuest "$VMX" 'C:\Windows\System32\cmd.exe' "/c tar -czf C:\\Users\\Public\\winout.tgz -C $G\\winrepro out" >/dev/null 2>&1 \
    && gop copyFileFromGuestToHost "$VMX" 'C:\Users\Public\winout.tgz' "$t" >/dev/null 2>&1 && tar xzf "$t" -C "$STAGE" 2>/dev/null; rm -f "$t"; }
psu() { local f=$1; shift; gx powershell -NoProfile -ExecutionPolicy Bypass -File "Y:\\winrepro\\$f" "$@"; }
# vmrun's token for $GU is UAC-filtered (Administrators is deny-only), so SYSTEM work starts as the built-in
# Administrator (enabled by create.sh with the same password), which can create the sys-run scheduled task.
pss() { local f=$1; shift; GXU=${WIN_SU:-Administrator} gx powershell -NoProfile -ExecutionPolicy Bypass -File "Y:\\winrepro\\sys-run.ps1" -File "Y:\\winrepro\\$f" ${1:+-ArgLine "\"$*\""}; }
dl() { # download Windows installers on the Mac (a fresh VM cannot validate many TLS certs yet)
  local arch=${1:-arm64}; cd "$STAGE"
  local v; v=$(curl -s https://nodejs.org/dist/index.json | jq -r '[.[]|select(.lts)][0].version')
  ls node-$v-$arch.msi >/dev/null 2>&1 || curl -sSfLo node-$v-$arch.msi https://nodejs.org/dist/$v/node-$v-$arch.msi
  local gpat; [ "$arch" = arm64 ] && gpat='Git-.*-arm64\.exe$' || gpat='Git-.*-64-bit\.exe$'
  ls Git-*.exe >/dev/null 2>&1 || curl -sSfLO "$(curl -s https://api.github.com/repos/git-for-windows/git/releases/latest | jq -r --arg p "$gpat" '.assets[]|select(.name|test($p))|.browser_download_url' | head -1)"
  ls vc_redist.$arch.exe >/dev/null 2>&1 || curl -sSfLo vc_redist.$arch.exe https://aka.ms/vs/17/release/vc_redist.$arch.exe
  ls -1 node-*.msi Git-*.exe vc_redist.*.exe; cd - >/dev/null; }
case ${1:-status} in
  create) shift; "$HERE/fusion/create.sh" "$@" || exit 1
          WIN_VMX= WIN_VM=${WIN_VM:-winrepro} exec "$0" bootstrap ;;
  status) [ -n "$VMX" ] && [ -f "$VMX" ] || { echo "no Fusion VM (looked in $VMS); run: $0 create"; exit 1; }
          running && echo "$VM: running, tools $(vr checkToolsState "$VMX")" || { echo "$VM: not running"; exit 0; }
          gx 'ver & whoami & subst & echo %PROCESSOR_ARCHITECTURE%' ;;
  up) running || { echo "$VM is not running, starting"; vr start "$VMX" nogui; }
      for i in $(seq 1 30); do gx echo up 2>/dev/null | grep -q up && { echo "$VM ready"; exit 0; }; sleep 10; done
      echo "$VM not answering guest exec after 5 min"; exit 1 ;;
  down) vr suspend "$VMX" && echo "$VM suspended" ;;
  # a VM started nogui never gets a Fusion window; suspended, the app resumes it in one ("vmrun start gui" fails then)
  show) running && { vr suspend "$VMX" soft; sleep 5; }; open -a "VMware Fusion" "$VMX" && echo "resuming $VM in a Fusion window" ;;
  pkg) spec=${2:-${WIN_PKG_SPEC:-}}; [ -n "$spec" ] || { echo "usage: win.sh pkg <npm spec> (or set WIN_PKG_SPEC)"; exit 2; }
      reg=${WIN_NPM_REGISTRY:-}; d=$(mktemp -d); uc="$d/.npmrc"; (umask 077; : >"$uc")
      scope=""; [[ "$spec" == @*/* ]] && scope=${spec%%/*}
      if [ -z "$reg" ]; then uc="$HOME/.npmrc"; [ -f "$uc" ] || uc=/dev/null   # public npm / your own npmrc
      else feed=//${reg#*://}; feed=${feed%/}/
        case "$reg" in
          *pkgs[.]dev[.]azure[.]com*|*[.]visualstudio[.]com*) # Azure Artifacts; resource id is the public Azure DevOps app id
            tok=$(az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv) || { rm -rf "$d"; echo "az token failed: run az login"; exit 1; } ;;
          *npm.pkg.github.com*) tok=$(gh auth token) ;;
          *) tok=${NPM_TOKEN:-} ;;
        esac
        { [ -n "$scope" ] && echo "$scope:registry=https:$feed" || echo "registry=https:$feed"; [ -n "$tok" ] && echo "$feed:_authToken=$tok"; } >"$uc"; tok=
      fi
      (cd "$d" && npm pack "$spec" --userconfig "$uc" >/dev/null && tar xzf ./*.tgz); rc=$?; [ "$uc" = "$d/.npmrc" ] && rm -f "$uc"
      [ $rc = 0 ] || { rm -rf "$d"; echo "npm pack $spec failed (registry ${reg:-default}; Azure: az login, GitHub: gh auth)"; exit 1; }
      echo "packed $(cd "$d/package" && node -p 'require("./package.json").name+"@"+require("./package.json").version')"
      (cd "$d/package" && if command -v bun >/dev/null; then bun install --production; elif command -v pnpm >/dev/null; then pnpm install --prod; else npm install --omit=dev; fi) 2>&1 | tail -1
      sync_ps; sync_src "$d/package" ;;
  bootstrap) sync_ps; sync_src "${2:-}"
    arch=$(gx echo %PROCESSOR_ARCHITECTURE% | tr -d '\r ' | tr 'A-Z' 'a-z'); [ "$arch" = amd64 ] && arch=x64; echo "VM arch: $arch"; dl "$arch"
    for i in "$STAGE"/node-*.msi "$STAGE"/Git-*.exe "$STAGE"/vc_redist.*.exe; do gop copyFileFromHostToGuest "$VMX" "$i" "C:\\Users\\Public\\$(basename "$i")" || exit 1; done
    pss system-bootstrap.ps1; psu user-setup.ps1; echo "next: $0 login" ;;
  ps) sync_ps; shift; if [ "${1:-}" = -c ]; then shift; c=$*; gx powershell -NoProfile -Command "\"${c//%/%%}\""; else psu "$@"; fi ;;
  sys) sync_ps; shift; pss "$@" ;;
  login) [ -n "$IDC_URL" ] && [ -n "$IDC_REGION" ] || { echo "set IDC_URL (IAM Identity Center start URL) and IDC_REGION first"; exit 2; }
         # headless device flow: the VM has no visible window, so the consent step happens in the Mac browser
         echo "open the URL printed below in your Mac browser and allow access; this waits for it"
         "$0" ps -c "kiro-cli login --identity-provider $IDC_URL --region $IDC_REGION --use-device-flow" && echo "next: $0 pong" ;;
  pong) sync_ps; psu pong.ps1 ${2:+-Agent "$2"} ${3:+-Dir "$3"} ;;
  kiro) sync_ps; [ -n "${3:-}" ] && sync_src "$3"; rm -f "$OUT/repro.log"; touch "$OUT/repro.log"; gx "del $G\\winrepro\\out\\repro.log 2>nul" >/dev/null
        GX_FOLLOW=repro.log psu kiro-repro.ps1 -Scenarios "${2:-agent,fix}" > "$OUT/driver.log" 2>&1 & run=$!
        { tail -n +1 -f "$OUT/repro.log" | perl -pe 'BEGIN{$|=1} s/\0//g'; } & tp=$!; wait "$run"; sleep 1; pkill -P "$tp" 2>/dev/null; kill "$tp" 2>/dev/null; wait "$tp" 2>/dev/null; wait "$tp" 2>/dev/null; pull_out
        for s in $(echo "${2:-agent,fix}" | tr ',' ' '); do [ -f "$OUT/$s-kiro.log" ] && { echo "=== verdicts: $s"; python3 "$HERE/kiro-hook-verdicts.py" "$OUT/$s-kiro.log" | grep -v 'capture-hook'; }; done ;;
  verdicts) python3 "$HERE/kiro-hook-verdicts.py" "$OUT/$2-kiro.log" ;;
  ide) shift; sub=${1:-targets}; shift || true
      # cache the VM IP (override with WIN_IP); vmrun's lookup is bounded to 20 s
      vmip() { [ -n "${WIN_IP:-}" ] && { echo "$WIN_IP"; return; }; local c="$OUT/.vm-ip"
        [ -s "$c" ] && curl -s -m 3 "http://$(cat "$c"):9223/json/version" >/dev/null && { cat "$c"; return; }
        perl -e 'alarm 20; exec @ARGV' "$VMRUN" -T fusion getGuestIPAddress "$VMX" -wait | tr -d '\r ' | tee "$c"; }
      case $sub in
        install) sync_ps; arch=$(gx echo %PROCESSOR_ARCHITECTURE% | tr -d '\r ' | tr 'A-Z' 'a-z'); [ "$arch" = amd64 ] && arch=x64
          url=$(curl -s https://kiro.dev/downloads/ | grep -oE "https://prod\.download\.desktop\.kiro\.dev/releases/stable/win32-$arch/[^\"' ]+\.exe" | head -1)
          [ -n "$url" ] || { echo "no win32-$arch installer link on kiro.dev/downloads"; exit 1; }; echo "$url"
          curl -sSfLo "$STAGE/kiro-ide.exe" "$url" && push_file kiro-ide.exe && psu ide-install.ps1 ;;
        up) sync_ps; psu ide-launch.ps1 ${1:+-Workspace "$1"}; ip=$(vmip)
          mac=$(ifconfig | awk -v p="${ip%.*}." 'index($2,p)==1 && /inet /{print $2; exit}')   # the Mac's address on the VM's NAT subnet
          [ -n "$mac" ] || { echo "no Mac address on ${ip%.*}.0/24; is the VM on NAT?"; exit 1; }
          pss ide-port.ps1 -Mac "$mac" | grep -E 'Listen|^[0-9]'; echo "CDP: $ip:9223"; curl -s -m 5 "http://$(vmip):9223/json/version" | jq -r .Browser ;;
        shot) node "$HERE/kcdp.mjs" "$(vmip):9223" shot "${1:-$OUT/ide.png}" ;;
        *) node "$HERE/kcdp.mjs" "$(vmip):9223" "$sub" "$@" ;;
      esac ;;
  sync) sync_ps; sync_src "${2:-}" ;;
  push) [ -d "$SHARE/${2:-}" ] && [ -n "${2:-}" ] || { echo "usage: win.sh push <dir under $SHARE>"; exit 2; }; push "${2%/}" clean && echo "$SHARE/$2 -> Y:\\$2" ;;
  *) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 2 ;;
esac
