param(
    [switch]$Foreground,
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$module = Join-Path $root 'src\CodexContextMonitor.psm1'
Import-Module $module -Force -DisableNameChecking
$cfg = Get-MonitorConfig $ConfigPath
Initialize-MonitorStorage $cfg
$statePath = Join-Path $cfg.dataRoot 'state\monitor-state.json'
if (Test-Path $statePath) {
    $state = Get-Content -Raw $statePath | ConvertFrom-Json -AsHashtable
    if ($state.pid -and (Get-Process -Id $state.pid -ErrorAction SilentlyContinue)) {
        "Codex Context Monitor already running. PID: $($state.pid)"
        exit 0
    }
}

if ($Foreground) {
    Start-MonitorLoop -ConfigPath $ConfigPath
    exit 0
}

$log = Join-Path $cfg.dataRoot 'state\monitor.log'
$err = Join-Path $cfg.dataRoot 'state\monitor-errors.log'
$args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"","-Foreground")
if ($ConfigPath) { $args += @('-ConfigPath', "`"$ConfigPath`"") }
$p = Start-Process -FilePath 'pwsh' -ArgumentList $args -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError $err -PassThru
"Codex Context Monitor started. PID: $($p.Id)"
