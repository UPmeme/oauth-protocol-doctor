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

Write-Host "Running protocol inventory smoke test..."
& powershell -NoProfile -ExecutionPolicy Bypass -File $script -ListProtocols | Out-Null

Write-Host "Running output file smoke test..."
$tmp = Join-Path $env:TEMP "oauth-protocol-doctor-smoke.json"
if (Test-Path -Path $tmp) {
  Remove-Item -Path $tmp -Force
}
& powershell -NoProfile -ExecutionPolicy Bypass -File $script -Protocol codex -Json -OutFile $tmp | Out-Null
if (-not (Test-Path -Path $tmp)) {
  throw "Expected JSON output file to be created."
}
$saved = Get-Content -Path $tmp -Raw | ConvertFrom-Json
if ($saved.tool -ne "oauth-protocol-doctor") {
  throw "Unexpected tool name in saved JSON report."
}
Remove-Item -Path $tmp -Force

Write-Host "Running AppX manifest smoke test when available..."
$codexManifest = "C:\Program Files\WindowsApps\OpenAI.Codex_26.527.7698.0_x64__2p2nqsd0c76g0\AppxManifest.xml"
if (Test-Path -LiteralPath $codexManifest) {
  $appxJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Protocol codex -AppxManifestPath $codexManifest -Json
  $appxReport = $appxJson | ConvertFrom-Json
  if (-not $appxReport.appxPackages) {
    throw "Expected AppX package declarations in Codex manifest smoke test."
  }
}

Write-Host "Running explanation smoke test..."
$explanation = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Protocol codex -Explain
if (($explanation -join "`n") -notmatch "Bug report checklist") {
  throw "Expected explanation output to include bug report checklist."
}

Write-Host "Smoke tests passed." -ForegroundColor Green
