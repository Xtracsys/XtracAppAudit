# Install on another Mac

The supplied ZIP targets Apple Silicon (arm64), macOS 14.4 or later. Intel support has not been packaged or runtime-tested.

1. Copy App-Audit-1.5.1-macOS-arm64.zip and SHA256SUMS through AirDrop or a trusted LAN file share. Transfer the ZIP rather than the loose app bundle.
2. Optional integrity check: in Terminal, change to the download folder and run `shasum -a 256 -c SHA256SUMS`. Keep the archive filename unchanged. A matching checksum detects transfer changes; it does not authenticate the publisher by itself.
3. Fully quit an existing copy with App Audit → Quit App Audit (Command-Q). Closing its window can leave the old process running.
4. Double-click the ZIP in Finder and move App Audit.app to Applications. Replace an earlier copy only after quitting it. Launch the Applications copy.
5. This build is ad-hoc signed, not Developer ID signed or notarized. If macOS blocks your trusted copy, follow Apple's per-app Privacy & Security → Open Anyway instructions: https://support.apple.com/102445 . Do not disable Gatekeeper globally.
6. Set scan folders on each Mac. Full Disk Access is optional for broader coverage; unreadable folders remain scan warnings. Configure scheduled audits only after installing the app at its permanent path. Notification permission is needed for alerts.

Each Mac runs its own audit and stores its own settings. This release has no centralized LAN collector and does not install software updates for other apps. Existing audit data is kept separately from the app in the user's Library/Application Support/App Audit directory. Do not copy that directory as part of deployment.

## Update or roll back

Retain the earlier ZIP before upgrading. Quit the app fully and replace the Applications bundle. Keep settings and saved audits; do not delete user data to roll back. Compatibility with data written by newer releases is not guaranteed. If a schedule was enabled against another installation path, disable it in the old copy before moving and re-enable from Applications.

## Second-Mac acceptance check

Check launch, scan completion/coverage warnings, search and filters, header sorting in both directions, and CSV export. For Update/security columns, collect evidence or use rows with different values; identical Not checked values do not visibly reorder. Verify optional scheduled audits separately if you intend to use them. Record macOS version, chip and any issues before public release.
