param(
    [switch]$Latest,
    [int]$Last,
    [string]$From,
    [string]$To,
    [switch]$Json,
    [string]$ConfigPath
)

$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'src\CodexContextMonitor.psm1') -Force -DisableNameChecking
$cfg = Get-MonitorConfig $ConfigPath
New-MonitorReport -Config $cfg -Latest:$Latest -Last $Last -From $From -To $To -Json:$Json
