$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'src\CodexContextMonitor.psm1') -Force -DisableNameChecking

$tmp = Join-Path $root 'work\test-data'
if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
New-Item -ItemType Directory -Force (Join-Path $tmp 'codex\sessions\2026\09\12'), (Join-Path $tmp 'data') | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'fixtures\sample-session.jsonl') (Join-Path $tmp 'codex\sessions\2026\09\12\rollout-2026-09-12T10-00-00-11111111-1111-1111-1111-111111111111.jsonl')

$cfg = [pscustomobject]@{
    codexHome = (Join-Path $tmp 'codex')
    dataRoot = (Join-Path $tmp 'data')
    largeToolOutputChars = 5
    veryLargeToolOutputChars = 100000
    duplicateHandoffWindowSeconds = 30
}
Initialize-MonitorStorage $cfg
$state = @{ files = @{} }
$count1 = Invoke-MonitorScan $cfg $state
$count2 = Invoke-MonitorScan $cfg $state

if ($count1 -lt 5) { throw "Expected first scan metrics, got $count1" }
if ($count2 -ne 0) { throw "Expected incremental second scan 0, got $count2" }
$summary = Get-Content -Raw (Join-Path $cfg.dataRoot 'sessions\11111111-1111-1111-1111-111111111111.json') | ConvertFrom-Json -AsHashtable
if ($summary.firstInputTokensExact -ne 1000) { throw 'firstInputTokensExact failed' }
if ($summary.latestInputTokensExact -ne 500) { throw 'latestInputTokensExact failed' }
if ($summary.suspectedCompactions.Count -ne 1) { throw 'suspected compaction failed' }
if ($summary.truncatedToolOutputs -ne 1) { throw 'truncation failed' }
if (($summary.largestToolOutputs[0].commandName -match 'abc')) { throw 'secret redaction failed' }

$partial = Join-Path $tmp 'partial.jsonl'
'{"timestamp":"2026-09-12T10:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"input_tokens":1}}}' | Set-Content -NoNewline $partial
$fs = @{ offset=0; partial='' }
$chunk = Read-NewJsonLines $partial $fs
if ($chunk.lines.Count -ne 0 -or -not $chunk.partial) { throw 'partial line handling failed' }

'All tests passed.'
