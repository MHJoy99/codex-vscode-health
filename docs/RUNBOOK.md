# Codex VS Code Recovery Runbook — `renderer_ready_timeout`

Symptom: `[CodexWebviewProvider] Webview renderer did not become ready ... reason=renderer_ready_timeout`
Discriminator: backend `codex app-server` healthy (`Initialize received id=1`) — renderer/pressure problem, not dead backend.

> ## SAFETY — READ FIRST
> - NEVER kill/touch `php-fpm`, `mysql`, `nginx`, Reverb, queue workers, prod htdocs.
> - NEVER `pkill -f extensionHost`, NEVER kill newest `kilo serve`.
> - NEVER delete `~/.codex` files or sqlite rows. VACUUM only with backup, stopped only.
> - NEVER `rm -rf ~/.codex`.

Follow in order. Stop at first fix.

## Step 1 — Confirm backend healthy

```bash
pgrep -af "codex.*app-server" || echo "NO app-server process"
ls -t ~/.vscode-server/data/logs/*/exthost*/openai.chatgpt/Codex.log 2>/dev/null | head -n 5
grep -h "Initialize received id=1" $(ls -t ~/.vscode-server/data/logs/*/exthost*/openai.chatgpt/Codex.log 2>/dev/null | head -n 3) | tail -n 5
```

Green: `Initialize received id=1` present + `renderer_ready_timeout` present = this runbook applies.
If NO app-server and no log → go to Step 5 (reinstall).

## Step 2 — Read-only check

```bash
bin/vscode-health.sh; echo "exit=$?"
```

`0` healthy, `1` warning, `2` critical. Thresholds: mem warn<2500 crit<1500, load warn>6 crit>9, disk warn>=80 crit>=90, sqlite>100M.

If disk >=90% → STOP, free space before any update.

## Step 3 — Safe auto-fix

```bash
bin/vscode-health.sh --fix
pgrep -af "kilo serve --port 0"
```

Only removes older dupe `kilo serve` (keeps newest) + logs >14d. If only 1 kilo → do not kill. Never `pkill -f kilo`, never match php-fpm.

## Step 4 — Reload + single-extension test

1. `Ctrl+Shift+P` → `Developer: Reload Window`.
2. If persists → `Reload With Extensions Disabled` → enable only Codex, retry.
3. `pgrep -c -f "bootstrap-fork --type=extensionHost"` should be 1.

Do not pkill exthost. If still >1 → disable to 1–2 AI extensions, reload again.

## Step 5 — Reinstall on version drift

```bash
ls -d ~/.vscode-server/extensions/openai.chatgpt-*
```

If >1 or 0 installs, or drift (e.g. 26.5908 vs 26.908): uninstall via Extensions view, reload, install one current version, ensure client/server `code --version` match. Do not reinstall healthy single install. Do not update with disk >=90%.

## Step 6 — VACUUM (stopped only)

```bash
pgrep -af "codex.*app-server" || echo "STOPPED - safe"
du -sh ~/.codex ~/.codex/logs_2.sqlite
TS=$(date -u +%Y%m%dT%H%M%SZ); cp ~/.codex/logs_2.sqlite /tmp/logs_2.sqlite.bak.$TS; chmod 600 /tmp/logs_2.sqlite.bak.$TS
sqlite3 ~/.codex/logs_2.sqlite 'VACUUM;'
du -sh ~/.codex ~/.codex/logs_2.sqlite
```

If RUNNING → STOP, close Codex panel, confirm STOPPED, retry. On failure leave backup, do not DELETE rows.

Restore if corrupt: `cp /tmp/logs_2.sqlite.bak.<TS> ~/.codex/logs_2.sqlite`

## Step 7 — Windows client cache

Close VS Code, then:

```cmd
rmdir /s /q "%APPDATA%\Code\Cache"
rmdir /s /q "%APPDATA%\Code\GPUCache"
code --disable-gpu
```

Reopen normally, retry sidebar. Do not delete whole `%APPDATA%\Code`. If still failing and server HEALTHY → use `codex` CLI, file issue with Step 2 output + versions + log slice.

## Quick reference

| Step | Green |
|---|---|
| 1 | `Initialize received id=1` |
| 2 | `RESULT: HEALTHY exit=0` |
| 3 | 1x kilo, 0 old logs |
| 4 | Sidebar <30s |
| 5 | installs: 1 |
| 6 | sqlite <100M |
| 7 | Sidebar renders |

Fallback: `codex` CLI.
