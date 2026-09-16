#!/usr/bin/env bash
#
#  BDX — VS Code Remote health gate (prevents Codex sidebar `renderer_ready_timeout`)
#  =================================================================================
#  Why this exists: 2026-09-16 Codex UI failed with
#    `[CodexWebviewProvider] Webview renderer did not become ready ... reason=renderer_ready_timeout`
#  while the backend `codex app-server` was healthy (`Initialize received id=1`).
#  Contributing server-side pressure at failure time:
#    load 7.2 (6 vCPU), Mem avail ~1.8G, swap used 3.6G,
#    2x extensionHost (~1.5G) + 2x `kilo serve` (~1.4G) + ~20x php-fpm,
#    ~/.codex 459M (logs_2.sqlite 136M).
#
#  Usage:
#    bin/vscode-health.sh        # check only, read-only, safe in cron
#    bin/vscode-health.sh --fix  # check + safe fixes (dupe kilo, old logs only)
#
#  Safe by design:
#    - NEVER touches php-fpm / mysql / nginx / reverb / queue workers / prod htdocs
#    - NEVER kills the newest `kilo serve` or any extensionHost (would drop your SSH)
#    - NEVER deletes Codex sessions / sqlite rows; VACUUM only with backup + only
#      when app-server is stopped, otherwise prints the manual command and skips
#    - --fix only removes: older duplicate `kilo serve`, vscode-server logs >14d
#
set -euo pipefail

FIX=0
if [ "${1:-}" = "--fix" ]; then FIX=1; fi

cyan(){ printf '\033[36m▶ %s\033[0m\n' "$1"; }
pass(){ printf '\033[32m✔ %s\033[0m\n' "$1"; }
warn(){ printf '\033[33m⚠ %s\033[0m\n' "$1"; }
crit(){ printf '\033[31m✖ %s\033[0m\n' "$1"; }

WARN_COUNT=0
CRIT_COUNT=0
mark_warn(){ WARN_COUNT=$((WARN_COUNT+1)); warn "$1"; }
mark_crit(){ CRIT_COUNT=$((CRIT_COUNT+1)); crit "$1"; }

NPROC=$(nproc 2>/dev/null || echo 6)
# Thresholds tuned from the 2026-09-16 failure (6 vCPU, 7.8G RAM).
MEM_AVAIL_WARN_MB=2500
MEM_AVAIL_CRIT_MB=1500
SWAP_USED_WARN_MB=3000
LOAD_WARN=$(awk "BEGIN {print $NPROC}")
LOAD_CRIT=$(awk "BEGIN {print $NPROC*1.5}")
DISK_WARN_PCT=80
DISK_CRIT_PCT=90
CODEX_SQLITE_WARN_MB=100
CODEX_TOTAL_WARN_MB=400

cyan "VS Code remote health check (NPROC=$NPROC)"

# 1. Memory / swap
if command -v free >/dev/null 2>&1; then
  read -r MEM_AVAIL_MB SWAP_USED_MB <<<"$(free -m | awk '/^Mem:/{a=$7} /^Swap:/{s=$3} END{print a+0, s+0}')"
  cyan "Memory avail=${MEM_AVAIL_MB}M swap_used=${SWAP_USED_MB}M"
  if [ "$MEM_AVAIL_MB" -lt "$MEM_AVAIL_CRIT_MB" ]; then
    mark_crit "Memory avail ${MEM_AVAIL_MB}M < ${MEM_AVAIL_CRIT_MB}M — Codex webview will time out. Close tabs / disable unused AI extensions, then reload window."
  elif [ "$MEM_AVAIL_MB" -lt "$MEM_AVAIL_WARN_MB" ]; then
    mark_warn "Memory avail ${MEM_AVAIL_MB}M < ${MEM_AVAIL_WARN_MB}M — headroom low for Codex webview (290M assets)."
  else
    pass "Memory avail ${MEM_AVAIL_MB}M OK"
  fi
  if [ "$SWAP_USED_MB" -gt "$SWAP_USED_WARN_MB" ]; then
    mark_warn "Swap used ${SWAP_USED_MB}M — host is thrashing; expect 30s renderer timeouts."
  fi
else
  mark_warn "free(1) not found, skipping memory check"
fi

# 2. Load
if [ -r /proc/loadavg ]; then
  LOAD1=$(awk '{print $1}' /proc/loadavg)
  cyan "Load1=$LOAD1 (warn>$LOAD_WARN crit>$LOAD_CRIT)"
  if awk "BEGIN {exit ! ($LOAD1 > $LOAD_CRIT)}"; then
    mark_crit "Load $LOAD1 > $LOAD_CRIT — extension hosts starved."
  elif awk "BEGIN {exit ! ($LOAD1 > $LOAD_WARN)}"; then
    mark_warn "Load $LOAD1 > $LOAD_WARN — Codex renderer at risk."
  else
    pass "Load $LOAD1 OK"
  fi
fi

# 3. Disk (webview + sqlite need headroom; failure host was 84%)
DISK_PCT=$(df -P / | awk 'NR==2{gsub(/%/,"",$5); print $5}')
cyan "Disk / at ${DISK_PCT}% (warn>${DISK_WARN_PCT}% crit>${DISK_CRIT_PCT}%)"
if [ "$DISK_PCT" -ge "$DISK_CRIT_PCT" ]; then
  mark_crit "Disk ${DISK_PCT}% — free space before Codex/VS Code update."
elif [ "$DISK_PCT" -ge "$DISK_WARN_PCT" ]; then
  mark_warn "Disk ${DISK_PCT}% — cleanup recommended (old logs, rar/zip in repo root)."
else
  pass "Disk ${DISK_PCT}% OK"
fi

# 4. Duplicate kilo serve (leaked after reloads; failure had 2x ~1.4G total)
# Bracket trick avoids pgrep self-match inflating the count.
KILO_PIDS=$(pgrep -f "[k]ilo serve --port 0" || true)
KILO_COUNT=$(echo "$KILO_PIDS" | grep -c . || true)
# pgrep returns non-zero when empty; normalize
if [ -z "$KILO_PIDS" ]; then KILO_COUNT=0; fi
cyan "kilo serve processes: $KILO_COUNT"
if [ "$KILO_COUNT" -gt 1 ]; then
  mark_warn "Found $KILO_COUNT duplicate 'kilo serve' processes: $(echo "$KILO_PIDS" | tr '\n' ' ')"
  if [ "$FIX" = "1" ]; then
    # Keep newest (smallest elapsed), kill older ones only. Exact-match, never php-fpm.
    # etimes = elapsed seconds (numeric), avoids lexical etime sort bug.
    PIDCSV=$(echo "$KILO_PIDS" | tr -s '[:space:]' ',' | sed 's/^,//;s/,$//')
    NEWEST=$(ps -o pid=,etimes= -p "$PIDCSV" 2>/dev/null | sort -k2 -n | head -n 1 | awk '{print $1}' || true)
    if ! [[ "${NEWEST:-}" =~ ^[0-9]+$ ]]; then
      mark_warn "Could not determine newest kilo PID (PIDs raced?) — refusing to kill. PIDs: $(echo "$KILO_PIDS" | tr '\n' ' ')"
    else
      for p in $KILO_PIDS; do
        if [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" != "$NEWEST" ]; then
          cyan "Killing stale kilo serve $p (keeping newest $NEWEST)"
          kill -- "$p" 2>/dev/null || warn "Could not signal $p (already gone?)"
        fi
      done
      pass "Duplicate kilo serve cleanup attempted (kept $NEWEST)"
    fi
  else
    warn "Re-run with --fix to kill older duplicates (keeps newest). Never kills php-fpm."
  fi
elif [ "$KILO_COUNT" -eq 1 ]; then
  pass "Single kilo serve OK ($KILO_PIDS)"
else
  pass "No kilo serve running (fine if no VS Code window open)"
fi

# 5. Extension hosts (more than 1 usually means leaked restart loop)
EXTHOST_COUNT=$(pgrep -fc "[b]ootstrap-fork --type=extensionHost" || true)
cyan "extensionHost processes: $EXTHOST_COUNT"
if [ "$EXTHOST_COUNT" -gt 1 ]; then
  mark_warn "Found $EXTHOST_COUNT extensionHosts — reload loop or leaked window. Use 'Developer: Reload Window', do NOT pkill (drops SSH)."
else
  pass "extensionHost count OK"
fi

# 6. Codex bloat (slows list_threads; failure showed stale_rollout warnings + 136M sqlite)
if [ -d "$HOME/.codex" ]; then
  CODEX_TOTAL_MB=$(du -sm "$HOME/.codex" 2>/dev/null | awk '{print $1}')
  LOGS_MB=0
  [ -f "$HOME/.codex/logs_2.sqlite" ] && LOGS_MB=$(du -m "$HOME/.codex/logs_2.sqlite" 2>/dev/null | awk '{print $1}')
  cyan "~/.codex total=${CODEX_TOTAL_MB}M logs_2.sqlite=${LOGS_MB}M (warn total>${CODEX_TOTAL_WARN_MB}M / sqlite>${CODEX_SQLITE_WARN_MB}M)"
  if [ "$CODEX_TOTAL_MB" -gt "$CODEX_TOTAL_WARN_MB" ] || [ "$LOGS_MB" -gt "$CODEX_SQLITE_WARN_MB" ]; then
    if pgrep -f "[c]odex.*app-server" >/dev/null 2>&1; then
      mark_warn "Codex state bloated but app-server is RUNNING — not vacuuming. Stop VS Code Codex panel, then run: cp ~/.codex/logs_2.sqlite /tmp/ && sqlite3 ~/.codex/logs_2.sqlite 'VACUUM;'"
    else
      mark_warn "Codex state bloated and app-server stopped."
      if [ "$FIX" = "1" ]; then
        TS=$(date -u +%Y%m%dT%H%M%SZ)
        cp -- "$HOME/.codex/logs_2.sqlite" "/tmp/logs_2.sqlite.bak.$TS" 2>/dev/null || true
        chmod 600 "/tmp/logs_2.sqlite.bak.$TS" 2>/dev/null || true
        if pgrep -f "[c]odex.*app-server" >/dev/null 2>&1; then
          mark_warn "app-server restarted since check — skipping VACUUM (backup kept)"
        elif sqlite3 "$HOME/.codex/logs_2.sqlite" "VACUUM;" 2>/dev/null; then
          pass "VACUUM done, backup at /tmp/logs_2.sqlite.bak.$TS"
        else
          mark_warn "VACUUM failed or skipped (db busy?) — backup kept at /tmp/logs_2.sqlite.bak.$TS"
        fi
      else
        warn "Re-run with --fix (app-server stopped) to backup+VACUUM, or vacuum manually."
      fi
    fi
  else
    pass "Codex state size OK"
  fi
  # Stale rollout warnings hint
  if grep -rq "stale_rollout_path_retained" --include=Codex.log "$HOME/.vscode-server/data/logs" 2>/dev/null; then
    mark_warn "Codex.log shows stale_rollout_path warnings — history bloat, same VACUUM path above."
  fi
else
  pass "No ~/.codex dir (CLI never ran here)"
fi

# 7. Stale Codex extension installs (version drift caused 26.5908 vs 26.908 report)
CODEX_DIRS=$(ls -d "$HOME/.vscode-server/extensions/openai.chatgpt-"* 2>/dev/null || true)
CODEX_DIR_COUNT=$(echo "$CODEX_DIRS" | grep -c . || true)
if [ -z "$CODEX_DIRS" ]; then CODEX_DIR_COUNT=0; fi
cyan "Codex extension installs: $CODEX_DIR_COUNT"
if [ "$CODEX_DIR_COUNT" -gt 1 ]; then
  mark_warn "Multiple Codex installs: $CODEX_DIRS — uninstall in VS Code, rm leftovers, reinstall once."
elif [ "$CODEX_DIR_COUNT" -eq 1 ]; then
  pass "Single Codex install OK ($CODEX_DIRS)"
else
  mark_warn "No Codex extension found on server (client may have uninstalled it)."
fi

# 8. AI-extension pile-up (all activate onStartupFinished and fight the renderer)
AI_COUNT=0
for e in kilocode.kilo-code qwenlm.qwen-code-vscode-ide-companion rooveterinaryinc.roo-cline google.google-antigravity openai.chatgpt; do
  if ls -d "$HOME/.vscode-server/extensions/$e-"* >/dev/null 2>&1; then AI_COUNT=$((AI_COUNT+1)); fi
done
cyan "AI extensions installed: $AI_COUNT / 5 tracked"
if [ "$AI_COUNT" -gt 3 ]; then
  mark_warn "$AI_COUNT AI extensions compete for the 30s renderer budget — enable only what this workspace needs (Codex OR Kilo per window)."
else
  pass "AI extension count OK"
fi

# 9. Old VS Code logs (safe to prune)
LOGS_DIR="$HOME/.vscode-server/data/logs"
if [ -d "$LOGS_DIR" ]; then
  OLD_LOGS=$(find "$LOGS_DIR" -mindepth 1 -maxdepth 1 -type d -name "20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]*" -mtime +14 2>/dev/null | wc -l)
  cyan "VS Code log sets older than 14d: $OLD_LOGS"
  if [ "$OLD_LOGS" -gt 0 ]; then
    if [ "$FIX" = "1" ]; then
      find "$LOGS_DIR" -mindepth 1 -maxdepth 1 -type d -name "20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]*" -mtime +14 -print -exec rm -rf -- {} + 2>/dev/null || true
      pass "Pruned $OLD_LOGS old log sets"
    else
      mark_warn "$OLD_LOGS old log sets — re-run with --fix to prune (logs only, never sessions)."
    fi
  else
    pass "Log retention OK"
  fi
fi

# Summary
echo "---"
if [ "$CRIT_COUNT" -gt 0 ]; then
  crit "RESULT: CRITICAL ($CRIT_COUNT crit, $WARN_COUNT warn) — do NOT open 3 AI panels at once; free RAM, reload window."
  echo "Client-side if renderer still times out (renderer runs on your Windows box, not this server):"
  echo "  1) VS Code Command Palette > Developer: Reload With Extensions Disabled > enable only Codex, retry."
  echo "  2) Update Codex extension to latest, ensure local + remote VS Code are same version."
  echo "  3) Clear %APPDATA%\\Code\\Cache + GPUCache, retry; try --disable-gpu once for Electron crashes."
  echo "  4) Fallback stays working: 'codex' CLI in terminal."
  exit 2
elif [ "$WARN_COUNT" -gt 0 ]; then
  warn "RESULT: WARNING ($WARN_COUNT) — healthy enough now, but run with --fix and keep AI extensions to 1-2 per window."
  exit 1
else
  pass "RESULT: HEALTHY — Codex renderer budget looks safe."
  exit 0
fi
