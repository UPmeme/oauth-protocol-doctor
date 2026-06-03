param(
  [ValidatePattern("^[A-Za-z][A-Za-z0-9+.-]*$")]
  [string]$Protocol,

  [string]$CallbackUrl,

  [switch]$Json,

  [switch]$ListProtocols,

  [string]$OutFile
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

function Get-ProtocolInventory {
  $roots = @(
    @{ scope = "currentUser"; path = "HKCU:\Software\Classes" },
    @{ scope = "localMachine"; path = "HKLM:\Software\Classes" }
  )

  $items = New-Object System.Collections.Generic.List[object]

  foreach ($root in $roots) {
    if (-not (Test-Path -Path $root.path)) {
      continue
    }

    Get-ChildItem -Path $root.path -ErrorAction SilentlyContinue | ForEach-Object {
      $urlProtocol = Get-RegistryValue -Path $_.PSPath -Name "URL Protocol"
      if ($urlProtocol -ne $null) {
        $commandPath = Join-Path $_.PSPath "shell\open\command"
        $items.Add([ordered]@{
          protocol = $_.PSChildName
          scope = $root.scope
          displayName = Get-DefaultValue $_.PSPath
          command = Get-DefaultValue $commandPath
        })
      }
    }
  }

  return $items | Sort-Object protocol, scope
}

function Write-OutputOrFile {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [string]$Path
  )

  if ($Path) {
    $directory = Split-Path -Path $Path -Parent
    if ($directory -and -not (Test-Path -Path $directory)) {
      New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }
    Set-Content -Path $Path -Value $Text -Encoding UTF8
    Write-Host "Wrote report to $Path" -ForegroundColor Green
  }
  else {
    Write-Output $Text
  }
}

if ($ListProtocols) {
  $inventory = Get-ProtocolInventory
  if ($Json) {
    $text = $inventory | ConvertTo-Json -Depth 6
    Write-OutputOrFile -Text $text -Path $OutFile
    exit
  }

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("OAuth Protocol Doctor")
  $lines.Add("Registered URL protocols")
  $lines.Add("")

  if (-not $inventory) {
    $lines.Add("(none found)")
  }
  else {
    foreach ($item in $inventory) {
      $lines.Add("- $($item.protocol) [$($item.scope)]")
      if ($item.command) {
        $lines.Add("  $($item.command)")
      }
    }
  }

  Write-OutputOrFile -Text ($lines -join [Environment]::NewLine) -Path $OutFile
  exit
}

if (-not $Protocol) {
  throw "Specify -Protocol <name> or use -ListProtocols."
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
  $text = $report | ConvertTo-Json -Depth 8
  Write-OutputOrFile -Text $text -Path $OutFile
  exit
}

$outputLines = New-Object System.Collections.Generic.List[string]
$outputLines.Add("OAuth Protocol Doctor")
$outputLines.Add("Protocol: $protocolName")
$outputLines.Add("")
$outputLines.Add("Effective command:")
if ($effectiveCommand) {
  $outputLines.Add("  $effectiveCommand")
}
else {
  $outputLines.Add("  (not found)")
}
$outputLines.Add("")
$outputLines.Add("Parsed command:")
$outputLines.Add("  executable: $($parsed.executable)")
$outputLines.Add("  arguments:  $($parsed.arguments)")
$outputLines.Add("  note:       $($parsed.parseNote)")
$outputLines.Add("")
$outputLines.Add("Findings:")
foreach ($finding in $findings) {
  $outputLines.Add("  [$($finding.level)] $($finding.message)")
}
$outputLines.Add("")
$outputLines.Add("Suggested next steps:")
foreach ($suggestion in $suggestions) {
  $outputLines.Add("  - $suggestion")
}

Write-OutputOrFile -Text ($outputLines -join [Environment]::NewLine) -Path $OutFile
