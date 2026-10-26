#!/usr/bin/env bash
# Drive a Parallels Windows VM from the Mac for bug repros, with visible output.
# Usage: win.sh <cmd> [args]   (VM = $WIN_VM or the first Parallels VM)
#   status                      VM state + prlctl exec reachability + share mapping
#   show                        open the VM's window on the Mac (a VM started by prlctl/up runs windowless)
#   up                          start the VM if stopped and wait (<=5 min) until prlctl exec answers
#   pkg [spec]                  stage a PUBLISHED package instead of the checkout: npm pack <spec> (or $WIN_PKG_SPEC)
#                               from $WIN_NPM_REGISTRY (else public npm). Auth by registry host: Azure Artifacts
#                               (Azure DevOps pkgs host) -> az token, GitHub Packages -> gh token, else your ~/.npmrc.
#                               Installs prod deps, syncs to Y:\fw-src. Then: win.sh kiro agent
#   bootstrap                   fresh-VM fixes: roots, VC++ runtime, Node, Git (downloaded on the Mac), kiro-cli, framework copy
#   ps <file.ps1|-c "cmd"> ...  run a PowerShell script from the share (or inline) as the logged-in user, output streamed here
#   sys <file.ps1> ...          same, as SYSTEM (installs without UAC; file is copied to C:\Users\Public first)
#   login                       print the kiro-cli login command for the user to run IN the VM (browser step)
#   pong [agent] [dir]          visibility smoke: version, whoami, agent list, "reply with pong"
#   kiro <scenarios> [src]      Kiro hook repro scenarios (agent,nodeversion,default,subdir,hooktimeout,hookcrash,exit2,parent,fix); progress log streamed
#   verdicts <scenario>         per-hook exit code / timeout / blocked from Kiro's debug log slice
#   ide install                 download the latest Kiro IDE (win32-arm64|x64) on the Mac, signature-check + silent-install as the user
#   ide up [C:\path\to\ws]        (re)launch Kiro IDE on the desktop with CDP 127.0.0.1:9222, expose it as <VM-IP>:9223 to the Mac only
#   ide <targets|text|click|send|eval|evalmain|shot> [arg]   drive the IDE via kcdp.mjs (see that file); shot defaults to $OUT/ide.png
#   sync [src]                  re-copy ps assets + framework checkout (default $WIN_SRC, else the git repo at cwd) to the share
# Env: WIN_VM, WIN_SHARE (~/winshare, mounted in the VM as Y:), WIN_SRC, WIN_PKG_SPEC, WIN_NPM_REGISTRY,
#      IDC_URL + IDC_REGION (your IAM Identity Center start URL and region; required for `login`),
#      WIN_AGENT (kiro agent to test), WIN_INIT_CMD (installs .kiro into a probe repo; {src} = framework copy),
#      WIN_GATE_MATCH (regex for the gate hook command), WIN_IP (skip the VM IP lookup)
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
VM=${WIN_VM:-$(prlctl list -a -o name --no-header 2>/dev/null | head -1)}
SHARE=${WIN_SHARE:-$HOME/winshare}; STAGE=$SHARE/winrepro; OUT=$STAGE/out
IDC_URL=${IDC_URL:-}; IDC_REGION=${IDC_REGION:-}
mkdir -p "$OUT"
sync_ps() { rsync -a "$HERE/ps/" "$STAGE/"   # repro settings go in a file: quoting args through prlctl + PowerShell is fragile
  jq -n --arg agent "${WIN_AGENT:-}" --arg initCmd "${WIN_INIT_CMD:-}" --arg gateMatch "${WIN_GATE_MATCH:-}" \
    '{agent:$agent, initCmd:$initCmd, gateMatch:$gateMatch}' > "$STAGE/repro.json"; }
sync_src() { local src=${1:-${WIN_SRC:-$(git rev-parse --show-toplevel 2>/dev/null)}}
  [ -n "$src" ] && [ -d "$src" ] || { echo "no framework source: pass a source dir, set WIN_SRC, or run from inside the checkout"; exit 1; }
  rsync -a --delete --exclude .git --exclude coverage --exclude evals --exclude .wt --exclude node_modules/.cache "$src/" "$SHARE/fw-src/"; echo "framework $src -> Y:\\fw-src"; }
psu() { local f=$1; shift; prlctl exec "$VM" --current-user powershell -NoProfile -ExecutionPolicy Bypass -File "Y:\\winrepro\\$f" "$@" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'; }
pss() { local f=$1; shift; prlctl exec "$VM" --current-user powershell -NoProfile -Command "Copy-Item Y:\\winrepro\\$f C:\\Users\\Public\\ -Force" >/dev/null
        prlctl exec "$VM" powershell -NoProfile -ExecutionPolicy Bypass -File "C:\\Users\\Public\\$f" "$@" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'; }
dl() { # download Windows installers on the Mac (a fresh VM cannot validate many TLS certs yet)
  local arch=${1:-arm64}; cd "$STAGE"
  local v; v=$(curl -s https://nodejs.org/dist/index.json | jq -r '[.[]|select(.lts)][0].version')
  ls node-$v-$arch.msi >/dev/null 2>&1 || curl -sSfLo node-$v-$arch.msi https://nodejs.org/dist/$v/node-$v-$arch.msi
  local gpat; [ "$arch" = arm64 ] && gpat='Git-.*-arm64\.exe$' || gpat='Git-.*-64-bit\.exe$'
  ls Git-*.exe >/dev/null 2>&1 || curl -sSfLO "$(curl -s https://api.github.com/repos/git-for-windows/git/releases/latest | jq -r --arg p "$gpat" '.assets[]|select(.name|test($p))|.browser_download_url' | head -1)"
  ls vc_redist.$arch.exe >/dev/null 2>&1 || curl -sSfLo vc_redist.$arch.exe https://aka.ms/vs/17/release/vc_redist.$arch.exe
  ls -1 node-*.msi Git-*.exe vc_redist.*.exe; cd - >/dev/null; }
case ${1:-status} in
  status) prlctl list -a; [ -n "$VM" ] && { prlctl exec "$VM" cmd /c ver 2>&1 | tr -d '\r' | grep -v '^$'; prlctl exec "$VM" --current-user cmd /c "whoami & net use" 2>&1 | tr -d '\r' | grep -E '\\|OK' ; } ;;
  up) st=$(prlctl list -a -o status,name --no-header | awk -v v="$VM" '$2==v{print $1}')
      [ "$st" = running ] || { echo "$VM is $st, starting"; prlctl start "$VM" 2>&1 | tail -1; }
      for i in $(seq 1 30); do prlctl exec "$VM" --current-user cmd /c echo up 2>/dev/null | grep -q up && { echo "$VM ready"; exit 0; }; sleep 10; done
      echo "$VM not answering prlctl exec after 5 min"; exit 1 ;;
  show) open -a "Parallels Desktop" "$(prlctl list -i "$VM" | awk -F': ' '/^Home:/{print $2}')" && echo "opened $VM window" ;;
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
    arch=$(prlctl exec "$VM" cmd /c "echo %PROCESSOR_ARCHITECTURE%" | tr -d '\r ' | tr 'A-Z' 'a-z'); [ "$arch" = amd64 ] && arch=x64; echo "VM arch: $arch"; dl "$arch"
    prlctl exec "$VM" --current-user powershell -NoProfile -Command "Copy-Item Y:\\winrepro\\node-*.msi,Y:\\winrepro\\Git-*.exe,Y:\\winrepro\\vc_redist.*.exe C:\\Users\\Public\\ -Force"
    pss system-bootstrap.ps1; psu user-setup.ps1; echo "next: $0 login" ;;
  ps) sync_ps; shift; if [ "${1:-}" = -c ]; then shift; prlctl exec "$VM" --current-user powershell -NoProfile -Command "$*" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'; else psu "$@"; fi ;;
  sys) sync_ps; shift; pss "$@" ;;
  login) [ -n "$IDC_URL" ] && [ -n "$IDC_REGION" ] || { echo "set IDC_URL (IAM Identity Center start URL) and IDC_REGION first"; exit 2; }
         echo "In the VM, open Windows Terminal (PowerShell) and run:"; echo "  kiro-cli login --license pro --identity-provider $IDC_URL --region $IDC_REGION"
         echo "(browser: same start URL, expand region -> $IDC_REGION). Then: $0 pong" ;;
  pong) sync_ps; psu pong.ps1 ${2:+-Agent "$2"} ${3:+-Dir "$3"} ;;
  kiro) sync_ps; [ -n "${3:-}" ] && sync_src "$3"; rm -f "$OUT/repro.log"; touch "$OUT/repro.log"
        psu kiro-repro.ps1 -Scenarios "${2:-agent,fix}" > "$OUT/driver.log" 2>&1 & run=$!
        { tail -n +1 -f "$OUT/repro.log" | perl -pe 'BEGIN{$|=1} s/\0//g'; } & tp=$!; wait "$run"; sleep 1; pkill -P "$tp" 2>/dev/null; kill "$tp" 2>/dev/null
        for s in $(echo "${2:-agent,fix}" | tr ',' ' '); do [ -f "$OUT/$s-kiro.log" ] && { echo "=== verdicts: $s"; python3 "$HERE/kiro-hook-verdicts.py" "$OUT/$s-kiro.log" | grep -v 'capture-hook'; }; done ;;
  verdicts) python3 "$HERE/kiro-hook-verdicts.py" "$OUT/$2-kiro.log" ;;
  ide) shift; sub=${1:-targets}; shift || true
      # prlctl exec can hang; cache the VM IP (override with WIN_IP) and bound the lookup to 20 s
      vmip() { [ -n "${WIN_IP:-}" ] && { echo "$WIN_IP"; return; }; local c="$OUT/.vm-ip"
        [ -s "$c" ] && curl -s -m 3 "http://$(cat "$c"):9223/json/version" >/dev/null && { cat "$c"; return; }
        perl -e 'alarm 20; exec @ARGV' prlctl exec "$VM" --current-user powershell -NoProfile -Command "(Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias Ethernet).IPAddress" | tr -d '\r ' | tee "$c"; }
      case $sub in
        install) sync_ps; arch=$(prlctl exec "$VM" cmd /c "echo %PROCESSOR_ARCHITECTURE%" | tr -d '\r ' | tr 'A-Z' 'a-z'); [ "$arch" = amd64 ] && arch=x64
          url=$(curl -s https://kiro.dev/downloads/ | grep -oE "https://prod\.download\.desktop\.kiro\.dev/releases/stable/win32-$arch/[^\"' ]+\.exe" | head -1)
          [ -n "$url" ] || { echo "no win32-$arch installer link on kiro.dev/downloads"; exit 1; }; echo "$url"
          curl -sSfLo "$STAGE/kiro-ide.exe" "$url" && psu ide-install.ps1 ;;
        up) sync_ps; psu ide-launch.ps1 ${1:+-Workspace "$1"}; mac=$(ifconfig | awk '/inet 10\.211\.55\./{print $2; exit}')
          pss ide-port.ps1 -Mac "${mac:-10.211.55.2}" | grep -E 'Listen|^[0-9]'; echo "CDP: $(vmip):9223"; curl -s -m 5 "http://$(vmip):9223/json/version" | jq -r .Browser ;;
        shot) node "$HERE/kcdp.mjs" "$(vmip):9223" shot "${1:-$OUT/ide.png}" ;;
        *) node "$HERE/kcdp.mjs" "$(vmip):9223" "$sub" "$@" ;;
      esac ;;
  sync) sync_ps; sync_src "${2:-}" ;;
  *) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 2 ;;
esac
