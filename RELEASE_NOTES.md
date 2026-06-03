# v0.1.0

Initial public release of OAuth Protocol Doctor.

## Highlights

- Diagnose Windows URL protocol handlers used by OAuth desktop callbacks.
- Inspect `HKCU`, `HKLM`, and effective `HKCR` protocol registrations.
- Detect missing protocol registrations, missing `URL Protocol` markers, unquoted executable paths, and missing open commands.
- Generate text or JSON reports suitable for bug reports and AI-assisted debugging.
- Includes a Windows smoke test workflow for GitHub Actions.

## Example

```powershell
.\scripts\oauth-protocol-doctor.ps1 -Protocol codex -CallbackUrl "codex://oauth_callback?state=demo"
```

## Notes

The tool is read-only by default. It does not modify the registry, perform OAuth, or bypass organization policy.
