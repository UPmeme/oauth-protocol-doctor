param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern("^[A-Za-z][A-Za-z0-9+.-]*$")]
  [string]$Protocol,

  [string]$CallbackUrl,

  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Get-RegistryValue {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$Name = ""
  )

  try {
    $item = Get-ItemProperty -Path $Path -ErrorAction Stop
    if ($Name -eq "") {
      return $item."(default)"
    }
    return $item.$Name
  }
  catch {
    return $null
  }
}

function Get-DefaultValue {
  param([Parameter(Mandatory = $true)][string]$Path)

  try {
    $key = Get-Item -Path $Path -ErrorAction Stop
    return $key.GetValue("")
  }
  catch {
    return $null
  }
}

function Test-KeyExists {
  param([Parameter(Mandatory = $true)][string]$Path)
  return Test-Path -Path $Path
}

function Parse-Command {
  param([string]$Command)

  if ([string]::IsNullOrWhiteSpace($Command)) {
    return @{
      executable = $null
      arguments = $null
      quotedExecutable = $false
      parseNote = "empty command"
    }
  }

  $trimmed = $Command.Trim()
  if ($trimmed.StartsWith('"')) {
    $end = $trimmed.IndexOf('"', 1)
    if ($end -gt 1) {
      return @{
        executable = $trimmed.Substring(1, $end - 1)
        arguments = $trimmed.Substring($end + 1).Trim()
        quotedExecutable = $true
        parseNote = "quoted executable"
      }
    }
  }

  $firstSpace = $trimmed.IndexOf(" ")
  if ($firstSpace -gt 0) {
    return @{
      executable = $trimmed.Substring(0, $firstSpace)
      arguments = $trimmed.Substring($firstSpace + 1).Trim()
      quotedExecutable = $false
      parseNote = "unquoted executable split at first space"
    }
  }

  return @{
    executable = $trimmed
    arguments = ""
    quotedExecutable = $false
    parseNote = "single token command"
  }
}

function New-Finding {
  param(
    [ValidateSet("ok", "warn", "error", "info")][string]$Level,
    [string]$Message
  )
  return [ordered]@{
    level = $Level
    message = $Message
  }
}

$protocolName = $Protocol.TrimEnd(":")
$paths = [ordered]@{
  currentUser = "HKCU:\Software\Classes\$protocolName"
  localMachine = "HKLM:\Software\Classes\$protocolName"
  effective = "Registry::HKEY_CLASSES_ROOT\$protocolName"
}

$registrations = [ordered]@{}
foreach ($entry in $paths.GetEnumerator()) {
  $basePath = $entry.Value
  $commandPath = Join-Path $basePath "shell\open\command"
  $registrations[$entry.Key] = [ordered]@{
    path = $basePath
    exists = Test-KeyExists $basePath
    displayName = Get-DefaultValue $basePath
    urlProtocol = Get-RegistryValue -Path $basePath -Name "URL Protocol"
    command = Get-DefaultValue $commandPath
    commandPath = $commandPath
  }
}

$effectiveCommand = $registrations.effective.command
if (-not $effectiveCommand) {
  $effectiveCommand = $registrations.currentUser.command
}
if (-not $effectiveCommand) {
  $effectiveCommand = $registrations.localMachine.command
}

$parsed = Parse-Command $effectiveCommand
$findings = New-Object System.Collections.Generic.List[object]

if ($registrations.effective.exists -or $registrations.currentUser.exists -or $registrations.localMachine.exists) {
  $findings.Add((New-Finding ok "Protocol registration exists."))
}
else {
  $findings.Add((New-Finding error "Protocol registration was not found."))
}

if ($registrations.effective.urlProtocol -ne $null -or $registrations.currentUser.urlProtocol -ne $null -or $registrations.localMachine.urlProtocol -ne $null) {
  $findings.Add((New-Finding ok "URL Protocol marker exists."))
}
else {
  $findings.Add((New-Finding warn "URL Protocol marker is missing. Windows may not treat this as a URL scheme."))
}

if ($effectiveCommand) {
  $findings.Add((New-Finding ok "Open command was found."))
}
else {
  $findings.Add((New-Finding error "Open command was not found."))
}

if ($parsed.executable) {
  if ($parsed.executable -like "* *" -and -not $parsed.quotedExecutable) {
    $findings.Add((New-Finding error "Executable path contains spaces but is not quoted."))
  }
  elseif ($parsed.quotedExecutable) {
    $findings.Add((New-Finding ok "Executable path is quoted."))
  }

  if (Test-Path -LiteralPath $parsed.executable) {
    $findings.Add((New-Finding ok "Executable exists on disk."))
  }
  else {
    $findings.Add((New-Finding warn "Executable path could not be found on disk: $($parsed.executable)"))
  }

  if ($parsed.executable -match "(?i)(electron|codex|app)\.exe$" -and $parsed.arguments -match "%1") {
    $findings.Add((New-Finding info "Command passes the callback URL as an argument. If the app treats it as an app path, the app may need a vendor-side callback handling fix."))
  }
}

if ($CallbackUrl) {
  $escapedProtocolName = [regex]::Escape($protocolName)
  if ($CallbackUrl -notmatch "^${escapedProtocolName}:") {
    $findings.Add((New-Finding warn "Callback URL does not start with '${protocolName}:'."))
  }
  else {
    $findings.Add((New-Finding ok "Callback URL matches the protocol name."))
  }
}

$suggestions = New-Object System.Collections.Generic.List[string]
if (-not $effectiveCommand) {
  $suggestions.Add("Install or repair the desktop app that owns '${protocolName}:'.")
}
if ($parsed.executable -like "* *" -and -not $parsed.quotedExecutable) {
  $suggestions.Add("Quote the executable path in the protocol open command.")
}
if ($effectiveCommand -and $parsed.arguments -notmatch "%1") {
  $suggestions.Add("Ensure the protocol command passes the callback URL, usually as '%1'.")
}
$suggestions.Add("Retry OAuth from a fresh browser tab after restarting the desktop app.")
$suggestions.Add("If the app reports oauth_callback as an Electron app path, report the issue to the app vendor.")

$report = [ordered]@{
  tool = "oauth-protocol-doctor"
  protocol = $protocolName
  callbackUrl = $CallbackUrl
  registrations = $registrations
  effectiveCommand = $effectiveCommand
  parsedCommand = $parsed
  findings = $findings
  suggestions = $suggestions
}

if ($Json) {
  $report | ConvertTo-Json -Depth 8
  exit
}

Write-Host "OAuth Protocol Doctor" -ForegroundColor Cyan
Write-Host "Protocol: $protocolName"
Write-Host ""
Write-Host "Effective command:"
if ($effectiveCommand) {
  Write-Host "  $effectiveCommand"
}
else {
  Write-Host "  (not found)"
}
Write-Host ""
Write-Host "Parsed command:"
Write-Host "  executable: $($parsed.executable)"
Write-Host "  arguments:  $($parsed.arguments)"
Write-Host "  note:       $($parsed.parseNote)"
Write-Host ""
Write-Host "Findings:"
foreach ($finding in $findings) {
  Write-Host "  [$($finding.level)] $($finding.message)"
}
Write-Host ""
Write-Host "Suggested next steps:"
foreach ($suggestion in $suggestions) {
  Write-Host "  - $suggestion"
}
