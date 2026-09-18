param([string]$ConfigPath)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'src\CodexContextMonitor.psm1') -Force -DisableNameChecking
$cfg = Get-MonitorConfig $ConfigPath
$statePath = Join-Path $cfg.dataRoot 'state\monitor-state.json'
if (-not (Test-Path $statePath)) { "Codex Context Monitor: STOPPED"; exit 0 }
$state = Get-Content -Raw $statePath | ConvertFrom-Json -AsHashtable
if ($state.pid) {
    $p = Get-Process -Id $state.pid -ErrorAction SilentlyContinue
    if ($p) { Stop-Process -Id $state.pid; "Codex Context Monitor stopped. PID: $($state.pid)"; exit 0 }
}
"Codex Context Monitor: STOPPED"
