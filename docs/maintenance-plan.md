# Maintenance Plan

This project is maintained as a small, practical Windows diagnostics tool.

## Near-Term Issues

### Add AppX/MSIX protocol registration detection

Windows Store and MSIX-packaged desktop apps can declare URL protocols in
`AppxManifest.xml` instead of the classic `HKCU/HKLM\Software\Classes` registry
paths. The tool should detect these declarations and explain mismatches between
manifest declarations and effective shell registration.

Status: shipped in `v0.2.0` for current-user packages and explicit manifest paths.

### Improve Electron callback warnings

Some Electron apps treat a callback URL such as `codex://oauth_callback?...` as an
application path when the launcher is misconfigured. The tool should make that
failure mode easier to recognize.

### Add real-world examples

Add examples for VS Code, GitHub Desktop, Codex, and custom Electron apps.

## Release Rhythm

- `v0.1.x`: small CLI usability improvements.
- `v0.2.x`: deeper Windows registration detection.
- `v0.3.x`: richer examples and bug-report templates.
