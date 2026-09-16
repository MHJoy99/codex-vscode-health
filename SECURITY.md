# Security — codex-vscode-health

## Never paste / commit

- GitHub tokens (`ghp_*`, `gho_*`, `github_pat_*`), `GH_TOKEN`
- `~/.codex/auth.json` in whole or part
- `OPENAI_API_KEY`, any `*_TOKEN`/`*_SECRET`
- Private keys, `~/.ssh/*`, TLS keys
- Production `.env`, DB passwords
- `hosts.yml` unredacted, customer PII

## Scrub Codex.log before upload

```bash
cp ~/.vscode-server/data/logs/*/exthost*/openai.chatgpt/Codex.log /tmp/Codex.scrubbed.log
sed -E -i -e 's/(ghp_|gho_|github_pat_)[A-Za-z0-9_]+/\1<REDACTED>/g' -e 's/(Bearer )[A-Za-z0-9._~+\/-]+/\1<REDACTED>/gi' -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<EMAIL-REDACTED>/g' -e 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/<IP-REDACTED>/g' /tmp/Codex.scrubbed.log
grep -n "renderer_ready_timeout\|Initialize received" /tmp/Codex.scrubbed.log | head
```

Attach only a 200-line slice around the signature.

## If you leaked something

1. Revoke/rotate immediately.
2. Tell maintainer which commit contains it for history purge.
3. Do not paste the replacement in the issue.
