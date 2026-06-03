# Changelog

## 0.2.0

- Added AppX/MSIX manifest protocol detection.
- Added `-AppxManifestPath` for explicit manifest inspection.
- Added report output for AppX/MSIX package declarations.
- Added warnings for manifest declarations that do not have an effective shell command.

## 0.1.1

- Added `-ListProtocols` to inventory registered Windows URL protocols.
- Added `-OutFile` to save text or JSON reports.
- Improved CLI validation when neither `-Protocol` nor `-ListProtocols` is provided.

## 0.1.0

- Initial PowerShell CLI for diagnosing Windows OAuth callback protocols.
- Added text and JSON report output.
- Added smoke test coverage.
- Added issue templates for bug reports and diagnostic cases.
