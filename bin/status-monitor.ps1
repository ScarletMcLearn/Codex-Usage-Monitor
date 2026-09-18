param([string]$ConfigPath)

$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'src\CodexContextMonitor.psm1') -Force -DisableNameChecking
$cfg = Get-MonitorConfig $ConfigPath
$statePath = Join-Path $cfg.dataRoot 'state\monitor-state.json'
if (-not (Test-Path $statePath)) { "Codex Context Monitor: STOPPED"; exit 0 }
$state = Get-Content -Raw $statePath | ConvertFrom-Json -AsHashtable
$running = $false
if ($state.pid) { $running = [bool](Get-Process -Id $state.pid -ErrorAction SilentlyContinue) }
$sessions = @(Get-SessionSummaries $cfg)
"Codex Context Monitor: $(if($running){'RUNNING'}else{'STOPPED'})"
"PID: $($state.pid)"
"Started: $($state.startedAt)"
"Sessions tracked: $($sessions.Count)"
"Last scan: $($state.lastScan)"
"Last scan metrics: $($state.lastMetricCount)"
