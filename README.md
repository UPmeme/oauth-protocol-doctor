# OAuth Protocol Doctor

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)
![Platform](https://img.shields.io/badge/platform-Windows-0078D4)
![License](https://img.shields.io/badge/license-MIT-green)

Diagnose Windows URL protocol handlers used by OAuth desktop callbacks.

OAuth desktop apps often rely on custom callback URLs such as `codex://oauth_callback`,
`vscode://callback`, or `myapp://auth`. When Windows, a browser, or an Electron app
handles that URL incorrectly, the OAuth flow can fail with confusing errors.

`oauth-protocol-doctor` is a small PowerShell diagnostic tool that checks whether a
custom URL protocol is registered correctly and prints a clear, AI-friendly report.
It is designed for developers, support teams, and technically curious users who need
to debug "the browser finished OAuth, but the desktop app never received it."

## Why This Exists

This project started from a real Windows OAuth callback failure:

```text
Error launching app
Unable to find Electron app at C:\Program ...\oauth_callback?state=...
Cannot find module 'C:\Program ...\oauth_callback?state=...'
```

The root problem was not the Google OAuth consent screen. It was the local Windows
callback handoff.

## Features

- Checks `HKCU`, `HKLM`, and effective `HKCR` protocol registrations.
- Shows the command Windows will use for a protocol callback.
- Detects common issues:
  - missing protocol registration
  - missing `URL Protocol` marker
  - unquoted executable paths with spaces
  - callback URL being passed as an app path instead of an argument
  - executable path that does not exist
- Produces an optional JSON report for bug reports or AI-assisted debugging.
- Read-only by default. It does not modify the registry.

## Install

Clone the repository:

```powershell
git clone https://github.com/UPmeme/oauth-protocol-doctor.git
cd oauth-protocol-doctor
```

No dependencies are required beyond Windows PowerShell.

## Quick Start

Run from PowerShell:

```powershell
.\scripts\oauth-protocol-doctor.ps1 -Protocol codex
```

Generate JSON:

```powershell
.\scripts\oauth-protocol-doctor.ps1 -Protocol codex -Json
```

Check a sample callback URL:

```powershell
.\scripts\oauth-protocol-doctor.ps1 -Protocol codex -CallbackUrl "codex://oauth_callback?state=demo"
```

List registered URL protocols:

```powershell
.\scripts\oauth-protocol-doctor.ps1 -ListProtocols
```

Save a report to disk:

```powershell
.\scripts\oauth-protocol-doctor.ps1 -Protocol codex -Json -OutFile .\reports\codex.json
```

## Example Output

```text
OAuth Protocol Doctor
Protocol: codex

Effective command:
  "C:\Program Files\WindowsApps\OpenAI.Codex_...\app\Codex.exe" "%1"

Findings:
  [ok] Protocol registration exists.
  [ok] URL Protocol marker exists.
  [warn] Command targets an Electron app directly. Some Electron apps require an app-specific launcher.
  [ok] Executable path appears quoted.

Suggested next steps:
  - Retry OAuth from a fresh browser tab after restarting the desktop app.
  - If Electron treats oauth_callback as an app path, report this to the app vendor.
```

## JSON Report

The JSON mode is useful when pasting diagnostics into a bug report or an AI assistant:

```powershell
.\scripts\oauth-protocol-doctor.ps1 -Protocol codex -CallbackUrl "codex://oauth_callback?state=demo" -Json
```

## Test

```powershell
.\tests\smoke.ps1
```

## Roadmap

- Detect AppX/MSIX protocol registrations more deeply.
- Add optional `--FixSuggestion` output without changing the registry.
- Add examples for VS Code, GitHub Desktop, and custom Electron apps.
- Package as a PowerShell Gallery module.

## Scope

This tool does not perform OAuth, approve app consent, or bypass organization policy.
It only diagnoses the local Windows URL protocol registration used after OAuth consent.

## License

MIT
