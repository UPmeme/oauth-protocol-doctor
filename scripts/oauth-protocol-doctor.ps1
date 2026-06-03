param(
  [ValidatePattern("^[A-Za-z][A-Za-z0-9+.-]*$")]
  [string]$Protocol,

  [string]$CallbackUrl,

  [switch]$Json,

  [switch]$ListProtocols,

  [string[]]$AppxManifestPath,

  [switch]$Explain,

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
  param([string[]]$ManifestPaths)

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

  foreach ($appxProtocol in (Get-AppxProtocolDeclarations -ManifestPaths $ManifestPaths)) {
    $items.Add([ordered]@{
      protocol = $appxProtocol.protocol
      scope = "appx"
      displayName = $appxProtocol.packageName
      command = $appxProtocol.executable
    })
  }

  return $items | Sort-Object protocol, scope
}

function Get-AppxProtocolDeclarations {
  param(
    [string]$ProtocolName,
    [string[]]$ManifestPaths
  )

  $items = New-Object System.Collections.Generic.List[object]
  $manifestItems = New-Object System.Collections.Generic.List[object]

  foreach ($manifestPath in @($ManifestPaths)) {
    if (-not $manifestPath) {
      continue
    }

    if (Test-Path -LiteralPath $manifestPath) {
      $manifestItems.Add([ordered]@{
        packageName = Split-Path (Split-Path $manifestPath -Parent) -Leaf
        packageFullName = $null
        installLocation = Split-Path $manifestPath -Parent
        manifestPath = $manifestPath
      })
    }
  }

  try {
    foreach ($package in (Get-AppxPackage -ErrorAction Stop)) {
      if (-not $package.InstallLocation) {
        continue
      }

      $manifestPath = Join-Path $package.InstallLocation "AppxManifest.xml"
      if (Test-Path -LiteralPath $manifestPath) {
        $manifestItems.Add([ordered]@{
          packageName = $package.Name
          packageFullName = $package.PackageFullName
          installLocation = $package.InstallLocation
          manifestPath = $manifestPath
        })
      }
    }
  }
  catch {}

  $seenManifestPaths = New-Object System.Collections.Generic.HashSet[string]
  foreach ($manifestItem in $manifestItems) {
    $currentManifestPath = $manifestItem["manifestPath"]
    if (-not $currentManifestPath -or -not $seenManifestPaths.Add($currentManifestPath)) {
      continue
    }

    try {
      [xml]$manifest = Get-Content -LiteralPath $currentManifestPath -Raw -ErrorAction Stop
    }
    catch {
      continue
    }

    $protocolNodes = @($manifest.SelectNodes("//*[local-name()='Extension' and @Category='windows.protocol']/*[local-name()='Protocol']"))
    foreach ($protocolNode in $protocolNodes) {
      $name = $protocolNode.GetAttribute("Name")
      if (-not $name) {
        continue
      }

      if ($ProtocolName -and $name -ne $ProtocolName) {
        continue
      }

      $application = $protocolNode.SelectSingleNode("ancestor::*[local-name()='Application'][1]")

      $items.Add([ordered]@{
        protocol = $name
        packageName = $manifestItem["packageName"]
        packageFullName = $manifestItem["packageFullName"]
        installLocation = $manifestItem["installLocation"]
        manifestPath = $manifestItem["manifestPath"]
        applicationId = if ($application) { $application.GetAttribute("Id") } else { $null }
        executable = if ($application) { $application.GetAttribute("Executable") } else { $null }
      })
    }
  }

  return $items
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

function Get-ExplanationText {
  param(
    [Parameter(Mandatory = $true)]$Report
  )

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("OAuth Protocol Doctor Explanation")
  $lines.Add("Protocol: $($Report.protocol)")
  $lines.Add("")

  if ($Report.effectiveCommand) {
    $lines.Add("Summary:")
    $lines.Add("  Windows has an effective command for '$($Report.protocol):'. The browser should be able to hand callback URLs to the registered handler.")
  }
  elseif ($Report.appxPackages.Count -gt 0) {
    $lines.Add("Summary:")
    $lines.Add("  '$($Report.protocol):' is declared by an AppX/MSIX package manifest, but no effective classic shell command was found.")
    $lines.Add("  This can happen when a Store/MSIX app declares a protocol but Windows has not exposed or repaired the shell registration for the current user.")
  }
  else {
    $lines.Add("Summary:")
    $lines.Add("  No effective Windows registration was found for '$($Report.protocol):'. OAuth callbacks using this protocol are unlikely to reach the desktop app.")
  }

  $lines.Add("")
  $lines.Add("What this means:")

  if ($Report.callbackUrl) {
    $lines.Add("  The tested callback URL was '$($Report.callbackUrl)'.")
  }

  if (-not $Report.effectiveCommand -and $Report.appxPackages.Count -eq 0) {
    $lines.Add("  The local machine does not appear to know which app should receive this protocol.")
  }

  if (-not $Report.effectiveCommand -and $Report.appxPackages.Count -gt 0) {
    $lines.Add("  The app package claims the protocol, but the effective shell lookup does not provide a runnable command.")
    $lines.Add("  In OAuth flows, this usually points to a local callback handoff problem rather than a provider consent problem.")
  }

  if ($Report.parsedCommand.executable -and -not $Report.parsedCommand.quotedExecutable -and $Report.parsedCommand.executable -like "* *") {
    $lines.Add("  The executable path appears to contain spaces and is not quoted, which can cause Windows to split the command incorrectly.")
  }

  if ($Report.parsedCommand.executable -and $Report.parsedCommand.arguments -notmatch "%1") {
    $lines.Add("  The command does not appear to pass the callback URL argument, so the app may launch without receiving OAuth state.")
  }

  $lines.Add("")
  $lines.Add("Recommended next steps:")
  foreach ($suggestion in $Report.suggestions) {
    $lines.Add("  - $suggestion")
  }

  $lines.Add("")
  $lines.Add("Bug report checklist:")
  $lines.Add("  - App name and version")
  $lines.Add("  - Windows version")
  $lines.Add("  - Browser used for OAuth")
  $lines.Add("  - Sanitized callback protocol name")
  $lines.Add("  - This diagnostic output")
  $lines.Add("  - Do not include OAuth codes, state tokens, cookies, or account email addresses")

  return $lines -join [Environment]::NewLine
}

if ($ListProtocols) {
  $inventory = Get-ProtocolInventory -ManifestPaths $AppxManifestPath
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

$appxPackages = @(Get-AppxProtocolDeclarations -ProtocolName $protocolName -ManifestPaths $AppxManifestPath)

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

if ($appxPackages.Count -gt 0) {
  $findings.Add((New-Finding info "Protocol is declared by $($appxPackages.Count) AppX/MSIX package(s)."))
  if (-not $effectiveCommand) {
    $findings.Add((New-Finding warn "AppX/MSIX manifest declaration exists, but no effective classic shell command was found. The package registration may need repair."))
  }
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
if ($appxPackages.Count -gt 0 -and -not $effectiveCommand) {
  $suggestions.Add("If this is a Store/MSIX app, try repairing or re-registering the package so Windows exposes the protocol handler.")
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
  appxPackages = $appxPackages
  effectiveCommand = $effectiveCommand
  parsedCommand = $parsed
  findings = $findings
  suggestions = $suggestions
}

if ($Explain) {
  $text = Get-ExplanationText -Report $report
  Write-OutputOrFile -Text $text -Path $OutFile
  exit
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
$outputLines.Add("AppX/MSIX declarations:")
if ($appxPackages.Count -gt 0) {
  foreach ($package in $appxPackages) {
    $outputLines.Add("  - $($package.packageName) ($($package.applicationId))")
    $outputLines.Add("    manifest: $($package.manifestPath)")
    if ($package.executable) {
      $outputLines.Add("    executable: $($package.executable)")
    }
  }
}
else {
  $outputLines.Add("  (none found)")
}
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
