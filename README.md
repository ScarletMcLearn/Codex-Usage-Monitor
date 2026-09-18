# Codex Context Monitor

Local Windows PowerShell monitor for Codex session/context metrics.

It watches local Codex JSONL session files, reads only appended bytes after the first scan, stores normalized metadata, and generates compact reports you can paste into ChatGPT/Codex later.

It does **not** reduce token use by itself. It measures behavior so context-efficiency changes can be evaluated.

## What It Does

- Runs outside active Codex chats.
- Reads `%USERPROFILE%\.codex\sessions`.
- Collects exact token counts when Codex emits `token_count` events.
- Estimates tool-output and user-message tokens from character counts.
- Tracks tool calls, large outputs, truncation markers, and suspected compaction.
- Stores local JSONL metrics and per-session summaries.
- Generates Markdown, JSON, and comparison reports.

## What It Does Not Do

- No OpenAI API calls.
- No ChatGPT/Codex model calls.
- No network requirement.
- No Codex config changes.
- No writes to Codex session files.
- No full prompt, assistant response, or command-output storage by default.

## Requirements

- Windows 11
- PowerShell 7.x (`pwsh`)
- Local Codex data under `%USERPROFILE%\.codex`

## Install

Clone or keep this repository locally, then run commands from repo root:

```powershell
cd H:\Projects\Automation\Self\Codex-Usage-Monitor\Codex-Usage-Monitor
```

Optional local config:

```powershell
Copy-Item .\config\config.example.json .\config\config.json
```

## Start Monitoring

Background:

```powershell
.\bin\start-monitor.ps1
```

Foreground/debug:

```powershell
.\bin\start-monitor.ps1 -Foreground
```

## Status

```powershell
.\bin\status-monitor.ps1
```

## Stop

```powershell
.\bin\stop-monitor.ps1
```

## Reports

Latest session:

```powershell
.\bin\report.ps1 -Latest
```

Last 10 sessions:

```powershell
.\bin\report.ps1 -Last 10
```

Date range:

```powershell
.\bin\report.ps1 -From "2026-09-12" -To "2026-09-19"
```

JSON export:

```powershell
.\bin\report.ps1 -Last 10 -Json
```

Comparison:

```powershell
.\bin\compare.ps1 -Before "2026-09-01,2026-09-11" -After "2026-09-12,2026-09-20"
```

## Data Locations

- `data/raw/YYYY-MM-DD.jsonl`: normalized metric events
- `data/sessions/<session-id>.json`: per-session summaries
- `data/reports/latest.md`: latest generated Markdown report
- `data/state/monitor-state.json`: offsets, PID, scan state
- `data/state/monitor-errors.log`: monitor errors

Runtime data is ignored by Git.

## Reset Data

```powershell
.\bin\reset-data.ps1 -ConfirmReset
```

This deletes monitor output only. It does not touch Codex data.

## Privacy

Default mode stores metadata only: token counts, timestamps, sizes, hashes, tool names, first command word, and incident flags.

It does not persist full prompts, full assistant responses, full command output, cookies, bearer tokens, passwords, API keys, or environment values.

See `docs/privacy.md`.

## Optional Windows Autostart

Use Task Scheduler manually if wanted:

1. Create Basic Task.
2. Trigger: At log on.
3. Action: Start a program.
4. Program: `pwsh`
5. Arguments:

```text
-NoProfile -ExecutionPolicy Bypass -File "H:\Projects\Automation\Self\Codex-Usage-Monitor\Codex-Usage-Monitor\bin\start-monitor.ps1"
```

Autostart is not installed by this repository.

## Tests

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
```

Fixtures are synthetic and anonymized.

## Known Limits

- Compaction is heuristic unless Codex emits a definitive local event. Reports label it `suspectedCompactions`.
- Estimated token counts use `ceil(characters / 4)` and are not tokenizer exact.
- By default, scanning is limited to the 20 newest session files modified in the last 14 days.
- First sight of a file reads only the last 1 MB, then switches to appended bytes. Tune `maxSessionFiles`, `maxSessionFileAgeDays`, and `initialReadBytes` in `config/config.json`.
- Tool duration exists only when matching completion metadata is present.
