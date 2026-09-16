# Contributing — codex-vscode-health

## How to add a new failure signature

Every check exists because a real failure was observed. Each new signature needs evidence:

1. **Log excerpt** — exact lines with context, e.g. `renderer_ready_timeout` + `Initialize received id=1`.
2. **Versions** — VS Code local + remote, every `openai.chatgpt-*` dir, `codex --version`, `uname -a`, `nproc`, `free -m`.
3. **Resource snapshot** — `free -m`, `loadavg`, `df -h`, `du -sh ~/.codex`, `pgrep -af "kilo serve|extensionHost|codex"`.
4. **Threshold justification** — why WARN vs CRIT.

Current thresholds (6 vCPU, 7.8G RAM baseline, failure at load 7.2 / avail 1.8G / swap 3.6G / ~/.codex 459M):

| Check | WARN | CRIT |
|---|---|---|
| Mem avail | <2500M | <1500M |
| Swap | >3000M | — |
| Load1 | >NPROC | >NPROC*1.5 |
| Disk | >=80% | >=90% |
| logs_2.sqlite | >100M | — |
| ~/.codex | >400M | — |
| kilo count | >1 | — |
| exthost count | >1 | — |
| AI ext | >3 | — |

## Rules

- Read-only by default. No kill/rm/VACUUM unless behind `--fix`.
- `--fix` allowlist only: older dupe kilo, logs >14d, VACUUM with backup when stopped.
- Never touch php-fpm/mysql/nginx/reverb/prod, newest kilo, any exthost, session rows.
- Exact-match `pgrep -f "kilo serve --port 0"` — never bare `kilo`.
- Exit codes 0/1/2 via mark_warn/mark_crit, never early exit.
- Test: `shellcheck`, `bash -n`, both run modes. Update CHANGELOG.
