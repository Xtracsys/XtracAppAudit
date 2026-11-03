# Xtracsys App Audit 1.5.1

Native, read-only macOS application inventory and evidence review.

## Changes

Fixes nonresponsive inventory sort headers for Update, Update age, Architecture, Signature, Publisher and Gatekeeper, and adds sorting for optional Notarization. Sort choice and direction persist. Update age uses evidence dates, not alphabetical age labels. Install-date sorting uses receipt evidence when available.

Adds JSON export for the currently visible, filtered application rows. Adds separate switches for online/trust checks and opt-in Bonjour discovery of local devices advertising supported services. Device discovery requires macOS Local Network permission and does not probe addresses or inspect remote apps.

## Downloads

- App-Audit-1.5.1-macOS-arm64.zip — Apple Silicon app, macOS 14.4+.
- App-Audit-1.5.1-source.zip — standalone source, public documentation and fixtures.
- SHA256SUMS — checksums for both versioned ZIPs.

The binary is ad-hoc signed. It is not Developer ID signed or notarized. Intel and older macOS are not supported by this download. No centralized LAN management is included.

## Verification and remaining checks

Local suite and release archive/signature checks are recorded in VERIFICATION.md. Live sorting was verified on the development Mac. Testing on a separate Mac and the first GitHub Actions run remain release-owner tasks. Do not describe those checks as complete until they pass.

Signature, Gatekeeper, notarization and update status are separate observations. Unknown is not a clean verdict. Review PRIVACY.md and SECURITY.md before sharing audit exports.
