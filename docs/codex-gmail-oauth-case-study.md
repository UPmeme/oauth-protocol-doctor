# Case Study: Codex Gmail OAuth Callback Failure on Windows

This case study documents a real OAuth callback failure involving the Codex desktop
app, the Gmail connector, Google OAuth, and Windows URL protocol handling.

Sensitive values such as account email addresses and OAuth state tokens have been
removed.

## Summary

After completing Google OAuth consent for the Gmail connector, the browser attempted
to return control to the Codex desktop app through a custom callback URL:

```text
codex://oauth_callback?state=...
```

Instead of completing authorization, Windows/Electron showed an app launch error.

## User-Visible Error

```text
Error launching app

Unable to find Electron app at C:\Program ...\oauth_callback?state=codex_scheme_oauth_s_...

Cannot find module 'C:\Program ...\oauth_callback?state=codex_scheme_oauth_s_...'
```

## Environment

- Platform: Windows x64
- App: Codex Desktop
- Package style: Microsoft Store / MSIX package
- Browser: Chrome
- Connector: Gmail
- OAuth provider: Google

## What Made This Confusing

The Google consent page succeeded far enough to request access to Gmail. The failure
happened after consent, when the browser tried to hand the OAuth result back to the
desktop app.

This means the issue was not primarily a Google permission problem. It was a local
callback handoff problem.

## Diagnostic Questions

The investigation focused on three questions:

1. Is the `codex:` URL protocol registered in classic Windows registry locations?
2. Does the Codex MSIX package declare the protocol in `AppxManifest.xml`?
3. Is there a mismatch between manifest declaration and effective shell registration?

## Example Diagnostic Command

```powershell
.\scripts\oauth-protocol-doctor.ps1 `
  -Protocol codex `
  -AppxManifestPath "C:\Program Files\WindowsApps\OpenAI.Codex_...\AppxManifest.xml"
```

## Example Finding

```text
Effective command:
  (not found)

AppX/MSIX declarations:
  - OpenAI.Codex_... (App)
    manifest: C:\Program Files\WindowsApps\OpenAI.Codex_...\AppxManifest.xml
    executable: app/Codex.exe

Findings:
  [error] Protocol registration was not found.
  [warn] URL Protocol marker is missing. Windows may not treat this as a URL scheme.
  [error] Open command was not found.
  [info] Protocol is declared by 1 AppX/MSIX package(s).
  [warn] AppX/MSIX manifest declaration exists, but no effective classic shell command was found.
```

## Interpretation

The protocol was declared by the MSIX package manifest, but the effective classic
shell registration did not expose an open command for `codex:`.

That mismatch can cause the browser-to-desktop OAuth callback to fail, even though
the OAuth provider and connector permissions appear correct.

The Electron error is especially misleading because it suggests Electron is looking
for an application at a path derived from the callback URL.

## What Did Not Solve It

The following actions did not reliably complete the Gmail connector authorization:

- Reinstalling Codex.
- Restarting Codex and Chrome.
- Re-registering the MSIX manifest while Codex was closed.
- Manually adding a classic `HKCU\Software\Classes\codex` protocol entry pointing to
  `Codex.exe "%1"`.

The manual registry entry was removed because it could still lead Electron to treat
the callback as an application path.

## Practical Takeaway

For desktop OAuth failures, separate the problem into two phases:

- Provider consent: Did Google/GitHub/Microsoft approve the OAuth request?
- Local callback handoff: Did Windows correctly route the custom URL back to the app?

In this case, the second phase failed.

## Vendor Bug Report

A similar issue was reported upstream in the OpenAI Codex repository:

```text
codex://oauth_callback handling fails on Windows with Electron launch error
```

When filing a vendor report, include:

- app version
- Windows version
- browser
- callback protocol name
- sanitized error text
- `oauth-protocol-doctor` text or JSON output

Do not include OAuth state tokens, authorization codes, cookies, or account email
addresses.
