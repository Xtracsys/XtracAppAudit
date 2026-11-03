# Privacy

Inventory, settings, audit snapshots and monitoring history are stored locally. App Audit has no telemetry or inventory upload service.

Manual or enabled scheduled update checks contact Homebrew's public catalog and HTTPS Sparkle feeds declared by apps. Providers receive normal request metadata; app-supplied feed URLs may contain identifiers. Gatekeeper assessment may contact Apple. Clicking a developer/support/release-notes link opens the browser and contacts that destination; manual links are user supplied and not independently verified.

The **Find network devices** switch is separate from online update and trust checks, starts Off each launch, and browses only the fixed Bonjour service types listed in the app bundle. macOS requests Local Network permission when discovery is first enabled. This can reveal service names and the local network interface; some devices advertise nothing supported and will not appear. Discovery runs only while enabled and the app scene is active. Hidden, minimized, or inactive scenes stop browsing and clear current results; discovery resumes if the switch remains On when the scene becomes active again. Results remain in memory and are not saved in settings, snapshots, monitor history, or app-list exports. App Audit does not probe subnet addresses or inspect remote applications. Online and trust checks controls the existing catalog, signing/Gatekeeper, and browser-link behavior; turning it Off preserves the existing Offline mode behavior.

Application Support/App Audit contains settings and monitor history. UserDefaults stores interface preferences. Explicit exports can contain app names, local paths, versions, receipt events and diagnostics. Scheduled history is always a full local audit, regardless of the export redaction toggle.

The optional LaunchAgent writes local `monitor.log` and `monitor-error.log` files under `Application Support/App Audit/Monitor/Logs`. Error diagnostics may include filesystem paths. These logs and audit data are not uploaded by App Audit.

The redaction option removes personal scan/app paths and web addresses from explicit JSON/CSV/HTML/PDF exports. The visible-app JSON export contains only the currently displayed, filtered app rows and their associated evidence; use a full audit snapshot for the complete inventory. Redaction is a best-effort sharing aid, not guaranteed anonymization: application names, identifiers, signing teams, versions and arbitrary diagnostic content can remain sensitive. Review files before sharing. Disabling redaction restores full exports; live inventory is never altered.

Default discovery traverses accessible filesystem directories, including hidden folders, mounted volumes and embedded app bundles; it reads app metadata without launching software. It does not read arbitrary document contents. Protected or unreadable paths are reported as coverage gaps. Full Disk Access may improve access, but is never granted or changed automatically. Notification permission is requested only by the explicit schedule-enable flow with notifications selected. Missing/unreadable evidence remains labeled.

## Workflow notes

Audit context and exception reasons/reviewers can identify clients or people. They are local and included in full exports; redacted exports omit context and exception free text. Current exception decisions persist in settings and copies in saved audits. Turning Online and trust checks Off skips online/trust checks and in-app browser links, including scheduled checks; already-running commands/requests may finish. The network-discovery switch does not change that setting. App Audit does not change system firewall settings or local-network permission on the user's behalf.
