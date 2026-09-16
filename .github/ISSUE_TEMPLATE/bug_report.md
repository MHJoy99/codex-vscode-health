---
name: Bug report
about: Codex sidebar renderer failure on VS Code Remote
title: "[bug] "
labels: bug
---

## 1. Symptom

- Error text:
- When (startup / reload / after N min / N AI panels):
- `bin/vscode-health.sh` result:

## 2. Codex.log excerpt

```log
paste ~30 lines around failure from ~/.vscode-server/data/logs/*/exthost*/openai.chatgpt/Codex.log
```

## 3. Versions

- VS Code client:
- VS Code server:
- Codex extension (`ls -d ~/.vscode-server/extensions/openai.chatgpt-*`):
- Codex CLI (`codex --version`):
- Remote OS:

## 4. Resources

```bash
free -m
uptime
ps -eo pid,etime,rss,comm --sort=-rss | head -20
df -h /
du -sh ~/.codex
```

## 5. Extensions

```text
code --list-extensions --show-versions | sort
```
