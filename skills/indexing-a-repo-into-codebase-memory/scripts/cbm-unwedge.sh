#!/usr/bin/env bash
# cbm-unwedge.sh: clear a wedged codebase-memory-mcp coordinator.
#
# Root cause it fixes: an index worker killed mid-run leaves orphaned
# pre-coordination / generation marker files in the /tmp coordination dir
# (cbm-daemon-<uid>/ under the system temp dir: the macOS realpath of /tmp,
# or /tmp elsewhere; override with CBM_COORD_DIR). New workers then refuse with
# "a pre-coordination or unverified CBM generation is active", and a daemon
# restart does NOT remove those /tmp files, so the wedge survives every
# restart and only clears on a full reboot (which wipes /tmp). This script
# reproduces the reboot's effect without rebooting: stop the daemon, back up
# and clear the coordination dir, respawn, verify. Index DBs are never touched.
#
# Usage:
#   cbm-unwedge.sh                 # diagnose + unwedge
#   cbm-unwedge.sh --dry-run       # diagnose only, change nothing
#   cbm-unwedge.sh --reindex <repo> [<repo> ...]   # unwedge then full-index repos (sequentially)
#   cbm-unwedge.sh --project <name>  # verify with index_status on this project (default: list_projects succeeds)
#   cbm-unwedge.sh --auto-reap       # for a scheduler: act only on recent wedge evidence, else no-op
# env: CBM_BIN (default: codebase-memory-mcp on PATH, else ~/.local/bin), CBM_COORD_DIR, CBM_PROBE_PROJECT
set -uo pipefail

UID_NUM="$(id -u)"
if [ -d /private/tmp ]; then _tmp=/private/tmp; else _tmp=/tmp; fi
COORD="${CBM_COORD_DIR:-${_tmp}/cbm-daemon-${UID_NUM}}"
CACHE="${HOME}/.cache/codebase-memory-mcp"
BACKUPS="${CACHE}/coord-backups"
BIN="${CBM_BIN:-$(command -v codebase-memory-mcp 2>/dev/null || echo "${HOME}/.local/bin/codebase-memory-mcp")}"
PROBE_PROJECT="${CBM_PROBE_PROJECT:-}"
DRY=0; REINDEX=0; AUTO_REAP=0; REPOS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --reindex) REINDEX=1 ;;
    --auto-reap) AUTO_REAP=1 ;;   # scheduled use: only act on aged orphan markers, else no-op
    --project) shift; PROBE_PROJECT="${1:-}" ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) [ $REINDEX -eq 1 ] && REPOS+=("$1") ;;
  esac; shift
done

log(){ printf '%s %s\n' "$(date +%H:%M:%S)" "$*"; }

log "coord dir: ${COORD}"
if [ ! -d "$COORD" ]; then log "no coordination dir present: nothing wedged here."; else
  log "coordination artifacts:"; ls -la "$COORD" 2>/dev/null | sed 's/^/    /'
fi

# Show current cohort identity if the healthy lifetime lock exists
LIFE="${COORD}/cbm-version-cohort-lifetime-v1.lock"
if [ -s "$LIFE" ]; then
  ver="$(strings "$LIFE" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  log "current cohort in lifetime lock: ${ver:-unknown}"
fi

# Orphaned per-generation markers (*.rw / *.turn without a live worker) are the usual culprit
ORPHANS="$(ls "$COORD"/*.rw "$COORD"/*.turn 2>/dev/null | wc -l | tr -d ' ')"
log "per-generation .rw/.turn markers present: ${ORPHANS}"

if [ "$DRY" -eq 1 ]; then log "--dry-run: no changes made."; exit 0; fi

# Scheduled/auto mode: act ONLY on concrete evidence of the wedge, not on the
# mere presence of markers (a *successful* index also leaves .rw/.turn markers
# that age, so marker-age alone would bounce a healthy daemon). The real symptom
# is that recent index workers FAIL with the wedge string. When the coordinator
# is wedged, every watcher-triggered index attempt writes a .worker-log-* saying
# "a pre-coordination or unverified CBM generation is active". If any such log
# was written in the last 15 minutes, we are genuinely wedged; otherwise no-op.
STAMP="${CACHE}/.cbm-last-unwedge"
if [ "$AUTO_REAP" -eq 1 ]; then
  # Cooldown: don't re-fire within 20 min of a prior unwedge. Stale failure logs
  # from a just-cleared wedge stay in the 15-min window briefly; the cooldown
  # keeps the reaper from bouncing an already-healthy daemon while they age out.
  if [ -f "$STAMP" ]; then
    age=$(( $(date +%s) - $(stat -f %m "$STAMP" 2>/dev/null || stat -c %Y "$STAMP" 2>/dev/null || echo 0) ))
    if [ "$age" -lt 1200 ]; then log "--auto-reap: unwedged ${age}s ago (<20m cooldown); leaving it to settle."; exit 0; fi
  fi
  WEDGED="$(find "$CACHE/logs" -maxdepth 1 -name '.worker-log-*' -mmin -15 2>/dev/null \
            | xargs grep -l 'pre-coordination or unverified' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${WEDGED:-0}" -eq 0 ]; then log "--auto-reap: no recent worker-failure evidence; coordinator healthy, nothing to do."; exit 0; fi
  log "--auto-reap: ${WEDGED} recent worker(s) failed with the wedge error -> unwedging."
fi

# 1) Stop ONLY the permanent daemon (leave per-client stdio servers alone; they reconnect)
if pgrep -f 'cbm-daemon-permanent' >/dev/null 2>&1; then
  log "stopping permanent daemon..."; pkill -f 'cbm-daemon-permanent' 2>/dev/null
  for i in 1 2 3 4 5; do pgrep -f 'cbm-daemon-permanent' >/dev/null 2>&1 || break; sleep 1; done
  pgrep -f 'cbm-daemon-permanent' >/dev/null 2>&1 && { log "daemon still alive, SIGKILL"; pkill -9 -f 'cbm-daemon-permanent'; sleep 1; }
  log "daemon stopped."
else
  log "no permanent daemon running."
fi

# 2) Back up then clear the coordination dir (== what a reboot does to /tmp). DBs untouched.
if [ -d "$COORD" ]; then
  mkdir -p "$BACKUPS"
  TS="$(date +%Y%m%dT%H%M%SZ)"; BK="${BACKUPS}/coord-${TS}.tar"
  tar -cf "$BK" -C "$(dirname "$COORD")" "$(basename "$COORD")" 2>/dev/null && log "backed up coord dir -> ${BK}"
  rm -f "$COORD"/* 2>/dev/null
  log "cleared coordination artifacts (index DBs in ${CACHE} left intact)."
fi

# 3) Respawn the daemon and verify coordination is healthy again
if [ -x "$BIN" ]; then
  log "respawning daemon via a probe call..."
  "$BIN" cli --json list_projects >/dev/null 2>&1
  sleep 2
  if [ -n "$PROBE_PROJECT" ]; then
    OUT="$("$BIN" cli --json index_status "{\"project\":\"${PROBE_PROJECT}\"}" 2>/dev/null)"
    if printf '%s' "$OUT" | grep -q '"status":"ready"'; then
      log "VERIFIED: coordination healthy, index_status=ready for ${PROBE_PROJECT}."
    else
      log "WARN: could not confirm ready (project may need a reindex). Raw:"; printf '%s\n' "${OUT:0:200}"
    fi
  elif "$BIN" cli --json list_projects >/dev/null 2>&1; then
    log "VERIFIED: daemon answers list_projects (pass --project <name> for a per-project check)."
  else
    log "WARN: list_projects failed after respawn."
  fi
fi

# 3b) Record the unwedge (cooldown stamp) and prune stale worker logs so the
#     just-cleared wedge evidence doesn't re-trigger the reaper, and the logs dir
#     (which balloons during a wedge loop) stays bounded.
touch "$STAMP" 2>/dev/null
PRUNED="$(find "$CACHE/logs" -maxdepth 1 -name '.worker-log-*' -mmin +5 2>/dev/null | wc -l | tr -d ' ')"
find "$CACHE/logs" -maxdepth 1 -name '.worker-log-*' -mmin +5 -delete 2>/dev/null
[ "${PRUNED:-0}" -gt 0 ] && log "pruned ${PRUNED} stale worker log(s)."

# 4) Optional full reindex (sequential, never parallel: parallel runs re-collide on admission)
if [ "$REINDEX" -eq 1 ] && [ "${#REPOS[@]}" -gt 0 ]; then
  for r in "${REPOS[@]}"; do
    log "full index: $r"
    "$BIN" cli --progress index_repository "{\"repo_path\":\"$r\",\"mode\":\"full\"}" 2>&1 | tail -3 | sed 's/^/    /'
  done
fi
log "done."
