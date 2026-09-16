# VS Code Health — Prevention Guide

> Context: `Codex renderer_ready_timeout`, load `7.2`, mem avail `1.8G`, swap `3.6G`, duplicate `kilo`/`exthost`, `~/.codex 459M`, `5–6` AI extensions, disk `84%`, drift `26.5908` vs `26.908`.

## 1. Thresholds

| Signal | Warn | Critical | Notes |
|---|---|---|---|
| Memory available | `< 2500 MB` | `< 1500 MB` | Failure at ~1800M under load |
| Load average (6 vCPU) | `> 6.0` | `> 9.0` sustained | Failure at 7.2 |
| Disk usage | `> 80%` | `> 90%` | Failure at 84% |
| `~/.codex` SQLite | `> 50M` monitor | `> 100M` | Failure at 136M/459M |
| Swap used | `> 1G` | `> 3G` | Failure at 3.6G |
| Duplicate helpers | `> 1` kilo or exthost | `>= 2` sets | Kill stale, reload |
| AI extensions/window | `3` | `>= 5` | Target 1–2 |
| Version drift | minor mismatch | major drift | Pin one version |

Check with `bin/vscode-health.sh`.

## 2. Extension hygiene — 1–2 per window

1. Max 1–2 AI extensions per window (Codex + Kilo, or Codex alone).
2. Never enable 5–6 simultaneously — each spawns exthost/sidecars.
3. One folder = one window. Two windows = dupe kilo/exthost + sqlite locks.
4. Pin Codex version; disable auto-update drift.
5. After changes: `Developer: Reload Window`, then `ps aux | grep -E 'exthost|kilo'`.

## 3. Swap / disk hygiene

```bash
free -h; swapon --show; ps aux --sort=-%mem | head -20
df -h / /root /tmp
du -sh ~/.codex ~/.vscode-server ~/.cache/* 2>/dev/null | sort -rh | head
```

Prune old logs, caches, stale worktrees. Keep 15% free. Never VACUUM or update with disk >90%.

## 4. `~/.codex` VACUUM (backup only, app-server stopped)

1. Stop all Codex/Kilo windows, confirm:
   ```bash
   ps aux | grep -E 'codex|kilo|exthost' | grep -v grep
   ```
   Proceed only when empty. Do not VACUUM while running.
2. Backup:
   ```bash
   TS=$(date -u +%Y%m%dT%H%M%SZ)
   mkdir -p ~/.codex/backups
   cp -a ~/.codex ~/.codex/backups/codex-pre-vacuum-"$TS"
   ```
3. VACUUM:
   ```bash
   for db in ~/.codex/*.db ~/.codex/*.sqlite; do [ -f "$db" ] || continue; sqlite3 "$db" "PRAGMA integrity_check;"; sqlite3 "$db" "VACUUM;"; done
   ```
4. Verify `integrity_check = ok`, relaunch one window, re-run health script.

## 5. Scheduled check

```bash
*/15 * * * * /root/codex-vscode-health/bin/vscode-health.sh >> ~/.codex/health.log 2>&1
```

Check-only in cron; never `--fix` unattended.

## 6. Windows client steps

1. `Developer: Reload With Extensions Disabled` → re-enable only pinned Codex.
2. Clear caches (VS Code closed):
   ```powershell
   Remove-Item -Recurse -Force "$env:APPDATA\Code\Cache"
   Remove-Item -Recurse -Force "$env:APPDATA\Code\GPUCache"
   ```
3. Test `code --disable-gpu` to isolate Electron/GPU faults.
4. Reconnect only after server health is green.
