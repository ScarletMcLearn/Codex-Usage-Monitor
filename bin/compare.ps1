param(
    [Parameter(Mandatory=$true)][string]$Before,
    [Parameter(Mandatory=$true)][string]$After,
    [string]$ConfigPath
)

$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'src\CodexContextMonitor.psm1') -Force -DisableNameChecking
$cfg = Get-MonitorConfig $ConfigPath
New-ComparisonReport -Config $cfg -Before $Before -After $After
