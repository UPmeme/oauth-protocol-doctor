# Contributing

Thanks for helping improve OAuth Protocol Doctor.

Useful contributions include:

- reports for real OAuth callback failures on Windows
- examples of protocol registrations from apps such as VS Code, GitHub Desktop, or Codex
- safer detection rules for Electron callback issues
- documentation improvements

## Development

Run the smoke test before opening a pull request:

```powershell
.\tests\smoke.ps1
```

Keep the tool read-only by default. Any registry-changing behavior should be explicit,
well documented, and guarded by a confirmation prompt.
