# Xtracsys App Audit 1.5.1

Native read-only macOS application inventory, audit snapshots and version review. Requires **macOS 14.4+**; included build is **Apple Silicon**. No administrator access or third-party dependencies.

Designed to make evidence reviewable: inspect installed apps without launching them, save and compare audit snapshots, and control online checks separately from Bonjour device discovery. Discovery is optional and limited to supported service announcements; it does not probe the subnet. [Read the Xtracsys orchestration playbook](https://github.com/Xtracsys/Xtracsys/blob/main/docs/ORCHESTRATION_GUIDE.md) for the planning and review workflow behind this project.

## Xtracsys identity

The supplied Xtracsys artwork appears in the app icon, inventory header, native About panel, standalone HTML and PDF reports. Rust `#B24630`, black and warm white `#F7F6F2` follow the supplied brand reference. Native controls retain system appearance and semantic status colours. The original artwork is preserved in `Sources/AuditCore/Resources/XtracsysLogo.png`; `Branding/AppIcon.icns` contains the macOS icon. Logo data is embedded locally in reports; no remote branding requests are made.

## Open

Open `dist/App Audit.app`. The ZIP is `dist/App-Audit-1.5.1-macOS-arm64.zip` (also available under the stable name `App-Audit-macOS-arm64.zip`). This is an ad-hoc signed local build, not Developer ID signed/notarized for distribution.

## Inventory and preferences

**Rescan** now searches the accessible filesystem (`/`) by default, including mounted volumes, hidden folders and nested helper `.app` bundles. **Folders** shows scope and coverage gaps, allows a custom scope, or restores the entire filesystem. Missing/unreadable paths produce warnings; device filesystem `/dev` is explicitly excluded because it is not application storage. Directory identities prevent loops and duplicate traversal through links and macOS aliases. Apps are read without launching them. This inventories `.app` bundles; standalone scripts, command-line tools, services and archive contents are not claimed as covered.

Search names, bundle IDs, versions or paths. Click any visible column heading to sort; click again to reverse direction. Update age sorts by evidence date. Filters include updates, unknown last use and apps needing security review (including uninspected apps). **Columns** controls date, security and location groups. Scan folders, search, filter, supported sort column/direction and column-group visibility persist locally between launches. Column widths/order are not persisted.

The switches beside the scan actions control **Online and trust checks** and **Find network devices** independently. Online and trust checks keeps the existing Offline mode behavior: On allows update/catalog checks, signing/Gatekeeper checks and browser links; Off skips those checks. Its setting is saved. Find network devices starts Bonjour discovery only while On and the app scene is active; it resets Off each launch and pauses with cleared results while hidden, minimized, or inactive. macOS asks for Local Network permission the first time. **View services** shows supported advertisements; quiet devices or devices without those services may not appear, and multiple services can belong to one device. Turning the switch Off stops discovery and clears the in-memory results. Nothing probes network addresses or inspects remote apps.

Select an app for full details. **Reveal in Finder** selects its bundle; double-click does the same. Apps are never launched by inspection. Architecture is read from the executable's Mach-O header, including universal binaries; script/missing executables remain Unknown.

## Saved audits and comparison

1. Finish scanning and any desired update/security checks.
2. Choose **Snapshots → Save full audit snapshot…** to save schema-versioned JSON containing the complete scan, scan roots/warnings, update checks, security results, receipt evidence, integrity hashes, policy and findings (schema 2; schema 1 remains readable). Search filters do not reduce the saved snapshot.
3. Later, **Open snapshot as baseline…** and rescan the current Mac. Or use the current scan as an in-memory baseline before making changes.
4. **Review changes** shows Added, Removed, Updated, Relocated, Relocated & updated, and Replaced. Matching uses exact paths first, then unique bundle IDs for moves. Duplicate identities are not guessed. Warnings flag different scan scopes or incomplete scans.
5. The **Saved audit evidence** tab reopens historical per-app details, including publisher, signing/Gatekeeper/notarization results, receipt events and update identity basis. These are saved observations, not new verification. Export either changes or the saved audit's full evidence as CSV.

**Export CSV** and **Export JSON** beside the scan actions contain the currently visible, filtered app rows and their available evidence. The JSON list export has its own format and is not a full snapshot; use **Save full audit snapshot…** for the complete audit.

Snapshots contain local paths and inventory; keep them private as appropriate. Imported snapshots are not authenticated. Comparison covers identity, version/build, path, signing team/status and collected SHA-256 evidence. Hash coverage is limited to the main executable, Info.plist and CodeResources; it does not detect every bundle modification. Baselines are explicitly chosen rather than reopened automatically.

## Security and install-date evidence

**Inspect security** inspects the visible rows sequentially; **Inspect security & receipts** in the detail panel inspects one app. **Stop** stops remaining work after the current bounded inspection. Prior evidence for apps still present is retained with its original timestamp and freshness checks.

- **Signature/publisher:** Apple's Security framework reads certificate identity, team and signed identifier. Apple's `codesign` verifies strictly across architectures and requires an Apple trust anchor. Invalid/unsigned/untrusted, unavailable and timed-out results remain distinct from a valid result. Signature validity does not establish absence of malware.
- **Gatekeeper:** `spctl --assess --type execute` reports Accepted, Rejected / assessment failed, Unavailable or Timed out. Assessment may consult Apple services. A Gatekeeper result can differ from strict resource validation.
- **Notarization:** reported as Confirmed by Gatekeeper only when an accepted assessment explicitly identifies Notarized Developer ID. Otherwise Not confirmed; that does not prove an app was never notarized. Diagnostics retain the tool output.
- **Dates:** `pkgutil` exact app/executable ownership queries are combined with bounded receipt-prefix/payload checks for receipts macOS reverse lookup misses. Only exact payload paths qualify. Package IDs, package versions, event dates and lookup failures/timeouts are retained. Latest matched receipt event is displayed; it may describe an update, not original installation. Multiple sources merge by package ID and newest event.
- **Fallback:** without matched receipt evidence, bundle filesystem creation is shown as an explicit estimate. Copying/restoration can change it. Last used is best-effort Spotlight data; Unknown does not mean never used.

Each external command has a timeout (4–20 seconds), capped output and forced termination if necessary. Receipt lookups cap owning packages and fallback candidates; partial/unavailable results are labeled. Stop does not interrupt the app currently being inspected, but skips subsequent apps.

## Online updates and identity

Checks run manually or through an explicitly enabled scheduled audit. The app downloads Homebrew's public cask catalog or the HTTPS Sparkle feed declared by an installed app. OS constraints, known cask variants, stable feed channels and numeric version/build comparisons are conservative. Ambiguous, incompatible, malformed and incomparable results never imply current.

A definitive Homebrew verdict requires an explicit bundle-ID/cask rule, valid Apple-anchored signature, matching signed identifier and expected Developer Team ID. Nine built-in publisher rules cover Chrome, Visual Studio Code, Firefox, Microsoft Edge, Microsoft Teams, GitHub Desktop, Telegram, Ollama and Cursor. Rules and observed signing provenance are in `Evidence.swift`. **Audit tools → Publisher registry** supports validated custom rules and JSON import/export; imports cannot override built-ins. Custom trust decisions require independent vendor verification. Other filename matches are **Unverified candidate** or **Possible update**, with latest catalog version/source visible for review. This deliberately limits verified coverage rather than asserting identity from a filename. Renamed app artifacts are handled. A signed Sparkle app feed uses the validated installed app's identity and clearly states that the feed URL is app-supplied; feed metadata is not a downloaded update signature verification.

Statuses include Managed by macOS, Manual check needed, Not checked, Update available, Current at source, Newer than source, Possible update, Unverified candidate, Unknown, Unsupported, App Store and Check failed. The counter counts **verified** updates. The Updates filter also includes possible updates requiring review. App Store applications link to Store updates.

HTTPS and system TLS validation are used with ephemeral sessions, response size limits, redirect checks and best-effort bounded DNS checks rejecting private destinations. DNS resolution is not pinned to the final connection, so this is not a guarantee against DNS rebinding. Check feeds only from apps you trust. Requests do not upload inventory, but providers see request metadata and app-supplied URLs may contain vendor identifiers. No installer is run. Update availability is not a CVE or vulnerability verdict.

## Update channels and app categories

Built-in apps/components in known macOS application, CoreServices and Cryptex application locations show **Managed by macOS** and bypass third-party catalog/feed matching. Use **System Settings → General → Software Update**. Store apps show **App Store** and bypass app-supplied feeds. Neither label confirms available updates or that the installed software is current; OS/Store availability is not queried.

Other apps with no automatic source match show **Manual check needed**. Older Unsupported results mean missing automatic coverage, not vendor end of support; displays use the clearer label. Routine unmatched-source findings are grouped into one coverage summary. Genuine update-check failures, inconclusive comparisons, security failures, changed hashes and policy violations remain visible. Known OS-managed components are excluded from legacy third-party catalog candidate findings.

The **Category** filter offers All apps, Third-party apps, Apple apps and System components and persists between launches. Categories use install locations or claimed Apple bundle metadata. A claimed `com.apple.*` identifier outside a macOS location does not receive macOS update routing or security trust. Third-party includes unclassified apps. Publisher/signature verification remains independent.

The age strip separates **OS-maintained** components from the 30/60/90-day groups, so normal OS file dates are not coloured as overdue individual apps. Original receipt/modification dates remain visible in details and reports. The full inventory is retained and All remains the default. Previously saved findings are historical observations; run a current audit for corrected grouping.

## Update age highlights

The **Update age evidence** strip shows clickable counts for **0–30**, **31–60**, **61–90**, **over 90 days** and **Unknown**. Click a band to filter; All restores the list. Dates columns include a colour-coded Update age label with text and provenance help. Details and exported reports show the underlying date/source. Old age is not a vulnerability verdict.

Age uses a matched installer receipt event when available, otherwise the latest bundle/Info/executable modification estimate. A receipt may describe installation or an update; copying, restoration and maintenance can change filesystem dates. Neither proves the vendor's actual last update. Missing/future dates are Unknown. Historical reports calculate age at capture time.

## Exceptions and audit context

In **Review findings**, select a finding and choose **Document / edit exception…**. A reason and reviewer are required. Set an expiry (default 30 days) or turn expiry off. The finding remains visible with its decision; active matching exceptions suppress new actionable monitor alerts without removing underlying evidence. Changed evidence, expiry or revocation requires review again.

**Audit tools → Exception register…** lists current, expired and revoked decisions and their reasons. Revoke when an exception no longer applies. Current decisions are stored locally; saved snapshots retain the decision at capture time. This is not an authenticated approval system or tamper-proof audit log. Reason/reviewer are omitted from redacted exports; the disposition remains visible.

**Audit context & notes…** records client, site/device label, auditor and notes. These appear in snapshots, HTML/PDF and CSV exports. Redacted exports omit context/free-text identity fields. Monitor context is copied when saving its options; current exception decisions are read each run.

## Evidence freshness and offline mode

Update, security and integrity records include a file-revision observation. The app refreshes selected-file metadata every 60 seconds while open, or via **Refresh evidence freshness**. File changes mark old observations stale; checks refuse to reuse an inventory revision that changed and ask for a Rescan. Rescan retains prior observations with their original timestamps and freshness labels. Only matching current revisions count as verified updates. Cheap size/mtime/inode checks are not cryptographic verification of every app file; legacy records show Freshness unknown.

The **Online and trust checks** switch beside the scan actions persists globally and is the inverse of Offline mode. When Off, it blocks catalog/Sparkle checks, signing/Gatekeeper inspections that may use Apple trust services, and in-app browser links. Inventory, hashes, policies, context and exports remain local. Scheduled audits re-read the saved setting before checks. A request or trust command already in progress may finish; this is an application control, not a system network firewall. Cached observations keep their recorded dates; no new online verdict is implied. Evidence is not automatically restored on relaunch; reopen a saved audit to review historical observations.

Local network discovery is a separate opt-in switch. It browses a fixed list of common Bonjour service types while the app scene is active; hidden, minimized, or inactive scenes stop browsing and clear current results. macOS Local Network permission is required. It reports advertised service names and types, not a complete device inventory. Results stay in memory and clear when discovery is turned Off or the scene stops being active. They are not included in audits, monitoring history or app-list exports.

## Developer addresses and duplicates

Select an app and choose **Edit developer links…**. Enter complete HTTPS website, support or release-note addresses and Save. The domain preview helps catch mistakes. Manual fields are labeled **User supplied** and take precedence over a catalog website. Clear and Save to restore the fallback. Known bundle IDs share links across moves/copies; apps without a usable ID use their exact path. Addresses persist in local settings and are included in saved snapshots/reports/CSV. Manual links never establish signing trust or change an update feed.

After an unambiguous Homebrew match, a valid HTTPS homepage is displayed as **Homebrew catalog supplied**, including when version compatibility is inconclusive. Sparkle-only checks do not supply a developer homepage; use manual addresses. No URL is guessed from an app name. Opening a link contacts the destination in your browser.

**Audit tools → Duplicate installations…** groups exact known bundle IDs at distinct paths, showing versions and Reveal buttons. A review finding also appears in audit reports. Unknown IDs and names alone are not grouped. Intentional copies, symlink aliases and backups can appear; nothing is deleted.

## Redacted exports

Enable **Audit tools → Redact personal paths & web addresses in exports** before saving JSON, CSV, change CSV or HTML/PDF. A visible banner marks the mode, filenames include Redacted, JSON carries a redacted marker and reports explain remaining sensitive data. The toggle applies to explicit exports for this session; live inventory and local scheduled history remain complete.

Personal app paths outside standard system/application locations receive consistent aliases across current/baseline exports. User/volume paths in diagnostics and web addresses are removed. App names, identifiers, versions, signing evidence and arbitrary diagnostic text can still identify software or its owner. Review every file before posting; this is not guaranteed anonymization. Keep original local snapshots for future comparisons: redacted paths cannot reliably match a later live scan.

## Integrity, findings and policy

**Audit tools → Collect integrity hashes** records streaming SHA-256 hashes for visible apps. Security inspection also collects hashes. Save a snapshot, then collect evidence in a later scan and compare. Same-version hash changes are actionable findings; versioned changes require review. File size, read-time and stability checks prevent silently trusting incomplete or changing files. Missing evidence remains Unknown.

**Findings** groups evidence into Action needed, Review and Unknown, each with a suggested next step. It includes audit coverage, verification failures, confirmed updates, integrity/signing changes and policy exceptions. Findings are evidence for review, not malware or CVE verdicts.

**Approved-app policy** is off by default. Configure allowed/blocked bundle IDs, optional minimum numeric versions, per-app or global trusted Apple team IDs, and optionally require every app to be listed. Per-app teams override global teams. Policies report exceptions and never block execution or uninstall software. Import/export JSON, review drafts and Save to apply. User settings are stored in `~/Library/Application Support/App Audit/settings.json`.

## Scheduled audits

**Audit tools → Scheduled audits & alerts** configures a daily local time, online checks, security inspection and notifications. **Enable daily audits** installs only App Audit's own user LaunchAgent. **Disable schedule** removes it. The schedule stays disabled until enabled. No test schedule is left installed.

Scheduled audits run with the window closed and always collect integrity hashes. The first run creates a quiet baseline. Later runs alert on newly observed apps, comparable changes and new actionable findings. Repeated unchanged findings and unknowns stay quiet. Incomplete/changed scopes suppress removal alerts; partial runs retain the last complete comparison baseline. Failed runs retain successful history. **Run audit now** uses the same runner without installing a schedule.

Current folders, policy and registry are copied when saving options, applying/enabling or running now. Later policy edits require saving monitor options again. Changing the scheduled time requires Apply daily schedule. Keep the app at its installed path and its drive available; the Mac must be logged in for the user LaunchAgent. Notifications require macOS permission, requested only by the enable action; delivery outcome appears in status.

Data and HTML history live under `~/Library/Application Support/App Audit/Monitor`; up to 30 audits are retained, protecting the latest/last complete baseline. History stores local paths and findings. **Review latest saved audit** opens the last successful background audit as saved evidence. No inventory is uploaded.

## Exports

**Export CSV** exports visible live rows; snapshots always save all inventoried rows. Live and saved CSV exports include date provenance, receipt IDs/events/lookup status, architecture, publisher/team/signed ID, signature, Gatekeeper, notarization, update identity basis and check timestamps. **Audit tools** and **Findings** export complete live or saved audits as standalone HTML or PDF, including coverage, findings/next steps, changes and application evidence. HTML escapes untrusted values and loads no external assets. PDF uses bounded native CoreText pagination, a 500-page limit and atomic final write. CSV includes integrity hashes and read errors. CSV fields are quoted and spreadsheet formula prefixes neutralized.

## Open-source contribution and publication

Code and documentation use **Apache-2.0**, with artwork governed separately by [brand terms](BRAND_TERMS.md). Read [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md) and [PRIVACY.md](PRIVACY.md). A macOS test/build workflow, issue/PR templates and a fictional sample audit are included.

The public source repository is [Xtracsys/XtracAppAudit](https://github.com/Xtracsys/XtracAppAudit) under Apache-2.0. Use this AppAudit directory as the repository root and follow [publication and maintenance](docs/GITHUB_RELEASE.md). Security reports can be sent to the contact in [SECURITY.md](SECURITY.md); GitHub Private Vulnerability Reporting is optional. The [macOS checks](https://github.com/Xtracsys/XtracAppAudit/actions/workflows/macos.yml) run on pushes. The local binary remains ad-hoc signed. `dist/SHA256SUMS` contains the versioned archive checksum.

## Build and verification

From this folder, with Xcode command-line tools / Swift 6+:

```sh
./scripts/build.sh
CLANG_MODULE_CACHE_PATH=/tmp/appaudit-clang SWIFTPM_MODULECACHE_OVERRIDE=/tmp/appaudit-swift \
  swift test --disable-sandbox --scratch-path /tmp/appaudit-tests
```

The build generates the `.app` and both ZIP names using a temporary build directory. Generated AppleDouble sidecars are excluded before signing and packaging.

Read-only development diagnostics:

```sh
"dist/App Audit.app/Contents/MacOS/AppAudit" --scan-json
"dist/App Audit.app/Contents/MacOS/AppAudit" --check-json
"dist/App Audit.app/Contents/MacOS/AppAudit" --inspect-json "/Applications/Example.app"
"dist/App Audit.app/Contents/MacOS/AppAudit" --snapshot-json /tmp/audit.json
"dist/App Audit.app/Contents/MacOS/AppAudit" --report-pdf /tmp/audit.json /tmp/audit.pdf
"dist/App Audit.app/Contents/MacOS/AppAudit" --export-audit /tmp/audit.json /tmp/shared.html --redact
"dist/App Audit.app/Contents/MacOS/AppAudit" --scheduled-audit /absolute/path/to/monitor.json
```

`--export-audit` accepts JSON, CSV, HTML or PDF output extensions; `--redact` removes personal paths/web addresses. It reads a saved audit and performs no new scan or online check.

The network smoke command selects installed Chrome, Code and Cursor; exits 2 if none is present. CLI sandbox restrictions may hide Spotlight/receipt evidence that the normal GUI can access.

## Source map

- `Sources/AuditCore/Inventory.swift`: scanner, inventory, version comparison, evidence CSV.
- `Sources/AuditCore/Snapshots.swift`: snapshot validation, comparison and change CSV.
- `Sources/AuditCore/Evidence.swift`: signing, publisher rules, receipts, Gatekeeper and Mach-O.
- `Sources/AuditCore/ProcessRunner.swift`: bounded read-only tool execution.
- `Sources/AuditCore/Preferences.swift`: validated local settings.
- `Sources/AuditCore/Updates.swift`: catalog/feed networking, compatibility and identity-based verdicts.
- `Sources/AuditCore/Integrity.swift`, `Findings.swift`, `Policy.swift`: hashes, findings and validated policy/registry.
- `Sources/AuditCore/Monitoring.swift`: locked headless audits, history and deduplicated changes.
- `Sources/AuditCore/Reports.swift`, `PDFReport.swift`: standalone HTML and native PDF.
- `Sources/AppAudit/NativeMonitor.swift`, `MonitorView.swift`, `PolicyViews.swift`, `FindingsView.swift`: scheduling, settings and findings UI.
- `Sources/AppAudit/AuditModel.swift`: async operations and file dialogs.
- `Sources/AppAudit/ContentView.swift`, `ComparisonView.swift`, `SavedAuditView.swift`: native UI.
- `Tests/AuditCoreTests/`: deterministic fixture/regression tests.
- `VERIFICATION.md`: evidence and remaining limits.

### Notarization evidence (1.4.2)

Notarization is available in the selected app’s security details and as an optional Columns → Notarization / distribution column, hidden by default. Accepted Gatekeeper sources distinguish Confirmed notarized (Notarized Developer ID), Apple system distribution, and App Store distribution. Distribution labels are not notarization verdicts and are never inferred from install location or claimed identity. Timeouts, unsuccessful assessments, and missing explicit evidence show Not established with a reason. Saved snapshots retain their original labels; inspect security again for current evidence. Gatekeeper may contact Apple services; this app does not submit software for notarization.

### Exception review queue (1.4.3)

Open Audit tools → Exception review queue. Filter decisions by overdue (expired), expiring within the next 30 days, changed evidence, active / no expiry, absent finding, or revoked. Counts and categories refresh each minute while open. Rows retain the reason, reviewer and expiry, expose current finding evidence and next step, and allow review / renewal through the existing exception editor. No-expiry decisions are not assigned an invented deadline. Absent findings remain recorded and are not treated as resolved. Revoked decisions remain separate; expired decisions remain overdue even if their finding is absent or changed. This adds no notification service or background job.

### Filesystem discovery (1.5.0)

Existing preferences using exactly the old four default app folders migrate to `/` automatically; intentionally customized scopes remain unchanged and can be broadened using Folders → Scan entire filesystem. Full scans may be slow on large, remote or backup volumes. Stop requests cancellation and returns an explicitly partial inventory after outstanding filesystem calls finish; a stalled mount can delay completion. scan warnings flow into findings, snapshots and HTML/PDF reports. Full Disk Access can improve access to protected user data, but the app does not elevate privileges, bypass protection or claim complete coverage of unreadable or unmounted storage. Scan progress displays the number of directories visited and current path.

## Project wiki

Open [`wiki/index.html`](wiki/index.html) for the offline user guide and project reference. Its interactive audit, snapshot-comparison, network-control, and scheduled-audit diagrams work offline; the File System tab lists the documented source files, tests, and release workflow. To update the wiki, edit `wiki/wiki_data.json` (and `wiki/template.html` only for layout changes), then run `python3 wiki/build.py`.

## Install and publish

See [LAN installation](docs/INSTALL.md), [release notes](docs/RELEASE_NOTES_1.5.1.md), and the [GitHub publication steps](docs/GITHUB_RELEASE.md). Version 1.5.1 includes the inventory column sorting fix.

## Contact

For GitHub project and security inquiries, contact **josh@xtracsys.com**. Send vulnerability reports privately by email or through GitHub Security when private reporting is enabled; do not post exploit details in a public issue.
