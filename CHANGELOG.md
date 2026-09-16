# Changelog — codex-vscode-health

All notable changes documented. Format based on Keep a Changelog, SemVer.

## [Unreleased]

## [0.1.0] — 2026-09-16

First release from 2026-09-16 incident (`renderer_ready_timeout` with healthy `Initialize received id=1`).

### Added

- `bin/vscode-health.sh`: mem/swap, load vs nproc, disk, dupe kilo handling, exthost count, ~/.codex bloat + stale_rollout hint, Codex installs, AI pile-up, old log pruning.
- Thresholds tuned from 6vCPU/7.8G host (failure at load 7.2 / avail 1.8G / swap 3.6G / ~/.codex 459M).
- docs/DIAGNOSIS.md, docs/PREVENTION.md, docs/RUNBOOK.md, CONTRIBUTING.md, SECURITY.md, CI, issue template.
