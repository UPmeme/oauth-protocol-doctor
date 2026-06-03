$ErrorActionPreference = "Stop"

$root = Split-Path $PSScriptRoot -Parent
$script = Join-Path $root "scripts\oauth-protocol-doctor.ps1"

Write-Host "Running text output smoke test..."
& powershell -NoProfile -ExecutionPolicy Bypass -File $script -Protocol codex | Out-Null

Write-Host "Running JSON output smoke test..."
$json = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Protocol codex -CallbackUrl "codex://oauth_callback?state=demo" -Json
$report = $json | ConvertFrom-Json

if ($report.tool -ne "oauth-protocol-doctor") {
  throw "Unexpected tool name in JSON report."
}

if ($report.protocol -ne "codex") {
  throw "Unexpected protocol in JSON report."
}

if (-not $report.findings) {
  throw "Expected at least one finding."
}

Write-Host "Smoke tests passed." -ForegroundColor Green
