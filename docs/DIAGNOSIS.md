# DIAGNOSIS — Codex Sidebar "Could Not Start Its User Interface" (Backend Healthy / Webview Dead)

> Incident date: `2026-09-16`
> VS Code: `1.132.0` · Codex ext installed: `26.5908.31748` (log self-reports `26.908.31748` — version drift)
> Host: 6 vCPU, `load ~7.2`, `mem avail 1.8G`, `swap 3.6G`

## 1. Symptoms

1. Codex sidebar fails to render; user-visible error: `could not start its user interface`
2. Backend **did start**: `Initialize received id=1`
3. Webview renderer never signals ready; 30s timeout:
   ` [CodexWebviewProvider] Webview renderer did not become ready elapsedMs=30001 reason=renderer_ready_timeout receivedWebviewMessage=true`
   - `elapsedMs=30001` = hard 30s readiness timeout.
   - `receivedWebviewMessage=true` = webview posted at least one message but never sent `ready`.
4. Host under memory + CPU pressure at time of failure.
5. Confounders: 2x `extensionHost` + 2x `kilo serve` + ~20x `php-fpm`, `~/.codex 459M` (`logs_2.sqlite 136M`), webview assets `290M`, 6 AI extensions.

**Classification: backend-healthy, webview-dead.** Do not reinstall backend, wipe auth, or rebuild server for this signature.

## 2. Environment snapshot

| Signal | Value |
|---|---|
| CPU | 6 vCPU, load `~7.2` (saturated) |
| Memory | avail 1.8G, swap 3.6G in use |
| Processes | 2x extensionHost, 2x kilo serve, ~20x php-fpm |
| Disk / bloat | `~/.codex 459M`, `logs_2.sqlite 136M`, webview assets `290M` |
| Extensions | 6 AI extensions |
| VS Code | `1.132.0` |
| Codex ext (installed) | `26.5908.31748` |
| Codex ext (log-reported) | `26.908.31748` — drift |
| Key log | `~/.vscode-server/data/logs/20260916T113016/exthost4/openai.chatgpt/Codex.log` |

## 3. Log paths + grep commands

```bash
ls -lt ~/.vscode-server/data/logs/ | head -20
ls -lh ~/.vscode-server/data/logs/*/exthost*/openai.chatgpt/Codex.log
grep -n "Initialize received" ~/.vscode-server/data/logs/20260916T113016/exthost4/openai.chatgpt/Codex.log | head -20
grep -n "CodexWebviewProvider\|renderer_ready_timeout\|did not become ready" ~/.vscode-server/data/logs/20260916T113016/exthost4/openai.chatgpt/Codex.log
grep -n -i "webview\|renderer\|ready\|timeout" ~/.vscode-server/data/logs/20260916T113016/exthost4/openai.chatgpt/Codex.log | tail -100
```

Positive backend marker: `Initialize received id=1`
Failure marker: `renderer_ready_timeout ... elapsedMs=30001 ... receivedWebviewMessage=true`

Rule out exthost crash:

```bash
grep -n -i "openai.chatgpt\|codex" ~/.vscode-server/data/logs/20260916T113016/exthost4/exthost.log | tail -100
grep -rn -i "activat.*fail\|extension host.*crash\|out of memory\|ENOMEM" ~/.vscode-server/data/logs/20260916T113016/ | head -50
```

Version drift check:

```bash
code --list-extensions --show-versions 2>/dev/null | grep -i -E "openai|chatgpt|codex|kilo|copilot|cline"
ls -ld ~/.vscode-server/extensions/openai.chatgpt-* 2>&1
```

## 4. Backend-healthy vs webview-dead

| Observation | This incident | Backend-dead | Full exthost-dead |
|---|---|---|---|
| `Initialize received id=1` | YES | NO | NO |
| `renderer_ready_timeout` | YES | usually NO | NO |
| `receivedWebviewMessage=true` | YES | false/absent | absent |
| Other sidebars render | mostly YES | YES | NO |

Rule: `Initialize` + `renderer_ready_timeout` + clean exthost log = investigate webview readiness under pressure.

`true` = webview JS ran but handshake incomplete (slow main-thread, blocked 290M bundle, throttled timer). `false` = JS never ran (CSP block, missing bundle, instant crash).

## 5. Resource checks

```bash
uptime; free -h; cat /proc/loadavg
ps aux --sort=-%cpu | head -30
ps aux --sort=-%mem | head -30
du -sh ~/.codex; ls -lh ~/.codex/*.sqlite*
du -sh ~/.vscode-server/extensions/openai.chatgpt-*
code --list-extensions --show-versions 2>/dev/null | sort
dmesg -T 2>/dev/null | grep -i -E "oom|killed process|out of memory" | tail -20
```

Observed: load 7.2/6 cores, avail 1.8G, swap 3.6G, 2x extensionHost + 2x kilo serve + ~20 php-fpm, `~/.codex 459M`.

## 6. Likely causes (ranked)

1. CPU/RAM starvation delays webview `ready` past 30s. Most likely.
2. Extension-host contention (6 AI extensions, 2x hosts).
3. Bloated bundle + sqlite pressure (290M assets + 136M sqlite).
4. Version drift (26.5908 vs 26.908) — stale webview HTML vs new handshake.
5. Renderer throttling under memory pressure.
6. Shared host noise (php-fpm pool confirms general-purpose box).

## 7. Next steps

1. Reload window once, re-grep timeout.
2. Reduce load, retry until load < core count.
3. Bisect extensions (Codex only, then re-enable one by one).
4. Resolve version drift, clear webview cache, retest.
5. VACUUM `~/.codex` with backup (app-server stopped).
6. Capture repro bundle for issue.

## 8. Evidence checklist

- [x] Sidebar error recorded
- [x] Backend marker (`Initialize received id=1`)
- [x] Webview marker (`elapsedMs=30001 ... receivedWebviewMessage=true`)
- [x] free/uptime/ps/du/extension-list documented
- [x] Version drift noted
