# codex-vscode-health

![status: experimental](https://img.shields.io/badge/status-experimental-orange)
![shell: bash](https://img.shields.io/badge/shell-bash-blue)
![shellcheck: TODO](https://img.shields.io/badge/shellcheck-TODO-lightgrey)
![license: MIT](https://img.shields.io/badge/license-MIT-green)

Health gate for Codex VS Code extension `renderer_ready_timeout` failures on remote hosts.

## 30-sec TL;DR

- Codex sidebar fails, but `codex app-server` backend is healthy.
- Failure signature: `[CodexWebviewProvider] Webview renderer did not become ready ... reason=renderer_ready_timeout`.
- Cause class: server-side memory / load pressure starves extensionHost, 30s webview budget expires.
- Fix path: run `bin/vscode-health.sh`, fix warnings, reload window, retry with 1 AI extension.
- CLI fallback (`codex` in terminal) keeps working when webview does not.

## Symptoms vs healthy backend

Symptomatic (client webview):

```text
[CodexWebviewProvider] Webview renderer did not become ready after 30000ms
reason=renderer_ready_timeout
```

Healthy backend (same incident, server log):

```text
codex app-server: Initialize received id=1
```

Interpretation: backend IPC works. Renderer (Electron, on your local machine) never signaled ready within 30s. Investigate host pressure + client extension state, not app-server protocol.

## Quickstart

```bash
git clone https://github.com/MHJoy99/codex-vscode-health.git
cd codex-vscode-health
chmod +x bin/vscode-health.sh

# read-only check, safe in cron/SSH
bin/vscode-health.sh

# check + safe fixes only
bin/vscode-health.sh --fix
```

Exit codes: `0` healthy, `1` warning, `2` critical.

`--fix` only does:

- kill older duplicate `kilo serve --port 0`, keep newest
- prune `~/.vscode-server/data/logs/20*` older than 14d
- backup + `VACUUM ~/.codex/logs_2.sqlite`, only when app-server stopped

It never touches php-fpm, mysql, nginx, reverb, queue workers, prod htdocs, newest `kilo serve`, extensionHost, or Codex session rows.

## Root-cause summary

Observed at 2026-09-16 failure time (6 vCPU, 7.8G RAM host):

- load 7.2, Mem avail ~1.8G, swap used 3.6G (thrashing)
- 2x extensionHost (~1.5G) + 2x `kilo serve` (~1.4G) + ~20x php-fpm
- `~/.codex` 459M, `logs_2.sqlite` 136M, `stale_rollout_path_retained` warnings
- disk `/` 84%
- Codex extension version drift (26.5908 on disk vs 26.908 in log)
- 5 AI extensions installed, all activate on `onStartupFinished`

Renderer budget is fixed at 30s. Above pressure delays extensionHost activation past that budget. Backend stays responsive because it has no such webview deadline.

Full analysis: `docs/DIAGNOSIS.md`.

## Repo layout

```text
bin/vscode-health.sh   # health check + safe --fix, no deps beyond coreutils/procps
docs/DIAGNOSIS.md      # incident evidence and causal chain
docs/PREVENTION.md     # extension hygiene, memory headroom, cron guidance
docs/RUNBOOK.md        # step-by-step triage when renderer times out
.github/workflows/    # CI (shellcheck)
.github/ISSUE_TEMPLATE/ # bug report template
```

## Docs

- [Diagnosis](docs/DIAGNOSIS.md)
- [Prevention](docs/PREVENTION.md)
- [Runbook](docs/RUNBOOK.md)

Read RUNBOOK first during an outage. Read DIAGNOSIS before changing thresholds in `bin/vscode-health.sh`.

## Contributing

- Keep script POSIX-adjacent bash, `set -euo pipefail`, no new runtime deps.
- Thresholds must cite measured incident data, not guesses.
- Never add destructive fixes (no pkill extensionHost, no php-fpm/mysql/nginx control, no session deletion).
- Run `shellcheck bin/vscode-health.sh` and `bash -n bin/vscode-health.sh` before PR.
- Report new `renderer_ready_timeout` cases via GitHub issue with script output + `free -m` + Codex extension version.

## License

MIT — see [LICENSE](LICENSE).
