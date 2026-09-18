# Architecture

PowerShell monitor reads Codex JSONL session files under `%USERPROFILE%\.codex\sessions`.

Flow:

1. `bin/start-monitor.ps1` starts hidden PowerShell loop or foreground mode.
2. `Start-MonitorLoop` polls session JSONL files.
3. `Read-NewJsonLines` reads only new bytes from last offset and keeps partial trailing line.
4. `Convert-CodexRecordToMetric` converts Codex events into privacy-preserving metrics.
5. Raw normalized metrics go to `data/raw/YYYY-MM-DD.jsonl`.
6. Aggregated per-session summaries go to `data/sessions/<session-id>.json`.
7. Reports read summaries only.

No OpenAI API, ChatGPT, Codex model call, or network call is used.
