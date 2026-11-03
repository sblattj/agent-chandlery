#!/usr/bin/env bash
# Build a Windows 11 arm64 VMware Fusion VM with no clicks: disk + .vmx + an unattend ISO, boot it windowless,
# press a key at "Press any key to boot from CD", wait for VMware Tools, then eject the install media.
# Usage: create.sh [iso]   (default: newest ~/Downloads/Windows11_Client_arm64_*.iso)
# Env: WIN_VM (name, default winrepro), WIN_VM_DIR (default ~/Virtual Machines.localized/<name>.vmwarevm),
#      WIN_GU (guest user, default winrepro; password in the keychain, service windows-vm-repro, created if missing),
#      WIN_MEM (MB, 8192), WIN_CPUS (4), WIN_DISK (128GB), WIN_SHARE (~/winshare, shared as "winshare")
# Progress: $WIN_SHARE/winrepro/out/create.log, screenshots in create.png. Bound: 75 min.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); LIB="/Applications/VMware Fusion.app/Contents/Library"
# vr: vmrun bounded at 60 s (guest ops can hang)
VMRUN="$LIB/vmrun"; vr() { perl -e 'alarm 60; exec @ARGV' "$LIB/vmrun" "$@"; }; VMCLI="$LIB/vmcli"; VDM="$LIB/vmware-vdiskmanager"
NAME=${WIN_VM:-winrepro}; DIR=${WIN_VM_DIR:-$HOME/Virtual Machines.localized/$NAME.vmwarevm}; VMX="$DIR/$NAME.vmx"
GU=${WIN_GU:-winrepro}; SHARE=${WIN_SHARE:-$HOME/winshare}; OUT=$SHARE/winrepro/out; LOG=$OUT/create.log
ISO=${1:-$(ls -t "$HOME"/Downloads/Windows11_Client_arm64_*.iso 2>/dev/null | grep -v " ([0-9]*)\.iso$" | head -1)}   # skip browser "(1)" copies
TOOLS_ISO="$LIB/isoimages/arm64/windows.iso"
mkdir -p "$OUT"; log() { echo "$(date +%H:%M:%S) $*" | tee -a "$LOG"; }
[ -x "$VMRUN" ] || { echo "VMware Fusion not installed"; exit 1; }
[ -f "$ISO" ] || { echo "no Windows arm64 ISO (pass one, or download it from microsoft.com/software-download/windows11arm64)"; exit 1; }
[ -e "$VMX" ] && { echo "$VMX exists; delete it or set WIN_VM"; exit 1; }
pw() { security find-generic-password -s windows-vm-repro -a "$GU" -w 2>/dev/null; }
[ -n "$(pw)" ] || security add-generic-password -s windows-vm-repro -a "$GU" -w "$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | cut -c1-16)Aa1"
mkdir -p "$DIR"
# unattend media: the password lives in it, so it is deleted once the guest answers
U=$(mktemp -d); (umask 077
  sed -e "s/__USER__/$GU/g" -e "s/__NAME__/$(echo "$NAME-vm" | tr 'a-z' 'A-Z' | cut -c1-15)/g" \
      -e "s/__PW__/$(pw)/g" "$HERE/autounattend.xml" > "$U/autounattend.xml"); (umask 077; perl -pe "s/__USER__/$GU/g; s/__PW__/$(pw)/g; s/\n/\r\n/" "$HERE/SetupComplete.cmd" > "$U/SetupComplete.cmd"); cp "$HERE/firstlogon.ps1" "$U/"
hdiutil makehybrid -quiet -iso -joliet -default-volume-name UNATTEND -o "$DIR/unattend.iso" "$U"; rm -rf "${U:?}"
"$VDM" -c -s "${WIN_DISK:-128GB}" -a lsilogic -t 0 "$DIR/$NAME.vmdk" >/dev/null || { log "disk create failed"; exit 1; }
cat > "$VMX" <<EOF
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "21"
displayName = "$NAME"
guestOS = "arm-windows11-64"
firmware = "efi"
memsize = "${WIN_MEM:-8192}"
numvcpus = "${WIN_CPUS:-4}"
pciBridge0.present = "TRUE"
pciBridge4.present = "TRUE"
pciBridge4.virtualDev = "pcieRootPort"
pciBridge4.functions = "8"
pciBridge5.present = "TRUE"
pciBridge5.virtualDev = "pcieRootPort"
pciBridge5.functions = "8"
pciBridge6.present = "TRUE"
pciBridge6.virtualDev = "pcieRootPort"
pciBridge6.functions = "8"
pciBridge7.present = "TRUE"
pciBridge7.virtualDev = "pcieRootPort"
pciBridge7.functions = "8"
nvme0.present = "TRUE"
nvme0:0.present = "TRUE"
nvme0:0.fileName = "$NAME.vmdk"
sata0.present = "TRUE"
sata0:0.present = "TRUE"
sata0:0.deviceType = "cdrom-image"
sata0:0.fileName = "$ISO"
sata0:1.present = "TRUE"
sata0:1.deviceType = "cdrom-image"
sata0:1.fileName = "unattend.iso"
sata0:2.present = "TRUE"
sata0:2.deviceType = "cdrom-image"
sata0:2.fileName = "$TOOLS_ISO"
ethernet0.present = "TRUE"
ethernet0.connectionType = "nat"
ethernet0.virtualDev = "vmxnet3"
ethernet0.addressType = "generated"
usb.present = "TRUE"
usb_xhci.present = "TRUE"
svga.present = "TRUE"
tools.syncTime = "TRUE"
isolation.tools.hgfs.disable = "FALSE"
sharedFolder.maxNum = "1"
sharedFolder0.present = "TRUE"
sharedFolder0.enabled = "TRUE"
sharedFolder0.readAccess = "TRUE"
sharedFolder0.writeAccess = "TRUE"
sharedFolder0.hostPath = "$SHARE"
sharedFolder0.guestName = "winshare"
sharedFolder0.expiration = "never"
EOF
log "created $VMX (iso $(basename "$ISO")); starting windowless"
"$VMRUN" -T fusion start "$VMX" nogui || { log "start failed"; exit 1; }
# the Windows ISO waits ~5 s for a key before falling through to the empty disk
for i in $(seq 1 20); do "$VMCLI" "$VMX" mks sendKeySequence "<enter>" >/dev/null 2>&1; sleep 1; done
START=$(date +%s); n=0
while :; do
  el=$(( $(date +%s) - START )); [ $el -ge 4500 ] && { log "guest not answering after 75 min; look at $OUT/create.png"; exit 1; }
  "$VMCLI" "$VMX" mks captureScreenshot "$OUT/create.png" >/dev/null 2>&1
  vr -T fusion -gu "$GU" -gp "$(pw)" fileExistsInGuest "$VMX" 'C:\Users\Public\firstlogon.log' >/dev/null 2>&1 \
    && vr -T fusion -gu "$GU" -gp "$(pw)" runProgramInGuest "$VMX" 'C:\Windows\System32\cmd.exe' '/c findstr done C:\Users\Public\firstlogon.log' >/dev/null 2>&1 \
    && { log "first logon done after ${el}s"; break; }
  n=$((n+1)); [ $((n % 6)) = 0 ] && { log "waiting (${el}s): tools $("$VMRUN" -T fusion checkToolsState "$VMX" 2>/dev/null)"
    # SetupComplete enables Administrator with the same password, so its log is readable even when the guest user is missing
    vr -T fusion -gu Administrator -gp "$(pw)" copyFileFromGuestToHost "$VMX" 'C:\Users\Public\firstlogon.log' "$OUT/firstlogon.log" >/dev/null 2>&1 \
      && log "guest log: $(tr -d '\r' < "$OUT/firstlogon.log" | grep -iE 'exit|error|completed' | tr '\n' '|')"; }
  sleep 20
done
# Tools is installed before the first logon; make sure guest ops answer, then eject the install media
sleep 30; for i in $(seq 1 30); do vr -T fusion -gu "$GU" -gp "$(pw)" runProgramInGuest "$VMX" 'C:\Windows\System32\cmd.exe' '/c ver' >/dev/null 2>&1 && break; sleep 10; done
"$VMRUN" -T fusion stop "$VMX" soft; sleep 5
sed -i '' -e 's/^sata0:[012]\.present = .*//' -e '/^sata0:[012]\./d' "$VMX"; sed -i '' '/^$/d' "$VMX"
rm -f "${DIR:?}/unattend.iso"
"$VMRUN" -T fusion start "$VMX" nogui && log "ready: $VMX (install media ejected, unattend.iso deleted)"
