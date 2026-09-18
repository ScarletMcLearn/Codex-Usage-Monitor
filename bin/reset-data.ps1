param([switch]$ConfirmReset)

if (-not $ConfirmReset) {
    "Refusing reset. Re-run with -ConfirmReset to delete local monitor data."
    exit 1
}
$root = Split-Path -Parent $PSScriptRoot
foreach ($rel in @('data\raw','data\sessions','data\reports','data\state')) {
    $path = Join-Path $root $rel
    if (Test-Path $path) { Remove-Item -LiteralPath $path -Recurse -Force }
    New-Item -ItemType Directory -Force $path | Out-Null
}
"Monitor data reset."
