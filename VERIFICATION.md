# App Audit 1.4.1 macOS update routing — 2026-10-22

- **58 tests passed, 0 failures**. Five routing regressions cover macOS path boundaries/Cryptex apps, claimed Apple namespace outside System receiving no OS route, OS/Store feed bypass, legacy false catalog matches removed while signature/policy findings stay, grouped unmatched coverage with real failures separate, and category/redacted classification round trips.
- Known macOS install locations route to Managed by macOS; Store apps route to App Store before any third-party feed or catalog matching. Both are channel classifications, not current-version verdicts or security trust. Claimed Apple category outside managed locations remains metadata only.
- Legacy unmatched Unsupported observations display Manual check needed with their original timestamp; routine no-source coverage becomes one Unknown. Actual failed/inconclusive checks, security/integrity/stale observations and policy findings remain visible. Valid Apple signatures without a team no longer falsely match the Needs review filter solely for lacking the exact string Valid.
- Persistent category filter added. OS-maintained age grouping avoids marking normal system-file age overdue; detailed evidence dates remain. Category/update channel are included in 44-column CSV and report workflow details. OS/Store update-availability timestamps are left blank/explicitly not checked rather than fabricated.
- Packaged live inventory: 232 apps, 204 OS-managed; categories 139 System components, 71 Apple apps, 22 Third-party/unclassified. Offline regression fixture replayed prior Unsupported/candidate statuses against all scanned paths. CSV/HTML/PDF confirmed managed labels, no false candidate findings, one grouped manual coverage item, 44-column CSV and blank OS/Store availability timestamps. PDF first page raster inspected, readable and unclipped.
- Independent read-only review reported no important defects. Existing collected user audit window was left running to preserve evidence. New native category/menu interactions were not exercised in that window; compiled UI and fixture tests checked. Save a snapshot before closing the prior build, then reopen 1.4.1 for the new presentation.
- No macOS updates installed, schedule activated or GitHub content published. Existing ad-hoc signing/macOS14.4 floor and older-OS/VoiceOver/dark-mode runtime limits remain.

- Final versioned/stable ZIP integrity/equality, extracted strict ad-hoc signature, executable permissions, 1.4.1 (7) metadata and extracted CLI classification export passed. SHA-256: `c1331bd4fb5e198d688bbd0c496903fe077f0f4cf74e98fc581bc9d394e22e1f`.

---

# App Audit 1.4.0 audit workflow — 2026-10-22

- Added mutually exclusive 0–30/31–60/61–90/>90-day and Unknown update-age bands, clickable inventory counts/filter, text/colour table highlights and date-source details. Native scan: 232 apps, bands 220/5/0/7/0; older filter displayed seven rows and All restored inventory. Age uses receipt events or modification estimates, not creation date as update proof. Historical exports use capture time.
- Findings have a decision column and reason/reviewer/expiry editor; register retains current/revoked decisions. Native editor, accessible required-reason label, expiry control and empty-field validation checked; cancelled draft without saving test decisions. Exceptions bind exact evidence, keep findings visible, stop suppressing action alerts after expiry/revocation/evidence change. Snapshots/reports/CSV preserve decisions; redaction omits private free text and preserves active disposition.
- Native context form and labelled notes editor inspected and cancelled. Context fields (client/site/auditor/notes) persist in settings and snapshots and appear in full reports. Redaction omits context. Offline mode guards network checks, trust/Gatekeeper inspection and in-app links; monitor checks global mode before each app/update and reads current exception decisions. Existing in-flight requests/commands may finish; this is not a firewall.
- Cached observations survive rescans with timestamps/revision labels. Periodic/manual size/mtime/inode refresh detects selected-file changes. Rechecks reject stale scanned revisions before doing work, so old version/feed metadata cannot acquire a new freshness stamp. Legacy missing revision evidence is Unknown; no whole-bundle guarantee.
- **53 tests passed**: eight workflow tests cover age boundaries/future dates, receipt precedence, reviewer/reason requirements, expiry/revocation/changed fingerprints/alert suppression, offline core and monitor guards, settings/snapshot/private-text redaction, revision changes and stale-scan rejection. Prior 45 tests retained.
- Independent review found stale-version rechecks could be marked fresh and empty reviewers were accepted. Fixed both with regressions and focused re-review; no further findings reported.
- Native controls use textual status alongside colour, labelled editors, required-field announcements, standard date/expiry controls and keyboard default/cancel actions. AX labels inspected. Full VoiceOver and dark-mode runtime walkthroughs and older macOS runtime testing were not performed. Build floor remains macOS14.4; Apple Silicon/macOS27 runtime checked.
- `security find-identity -v -p codesigning` found zero valid identities visible in this session. Developer ID signing/notarization remains unavailable; local build is ad-hoc signed. No GitHub publication/CI run or schedule/notification activation performed.

- Final packaged CLI exported full/redacted JSON, 42-column CSV, HTML and PDF from the fictional sample. Full context/reason/reviewer retained; redacted private free text absent; active exception state preserved. PDF text and first-page layout checked. ZIP integrity/equality, extracted strict signature/metadata/executable and extracted-app report passed. `vtool` confirms minos14.4. ZIP SHA-256: `c6eb2e0d40838aad127fed7ae12696f5386ff034bd1419c8d7a1ac3fe7f79e0f`.

---

# App Audit 1.3.0 community features — 2026-10-22

- **45 tests passed, 0 failures**: five new tests cover manual-link validation/persistence and older settings, duplicate identities, redacted evidence key/comparison preservation, root-scan/mixed-case URL privacy, and optional catalog homepage metadata.
- Native editor displayed per-bundle scope, domain preview, HTTP validation error and saved User supplied link. Temporary example.org link was cleared/saved afterward; no test link remains. New export-redaction menu toggle and visible status indicator checked. Duplicate installations native panel displayed its honest empty state for this scan. Final build opened the native CSV Save dialog successfully; cancelled without exporting private inventory. Full inventory/search restored.
- Packaged `--export-audit` exercised JSON, 34-column CSV, HTML and PDF against a fictional two-copy app fixture with personal paths and uppercase URL query/fragment secrets. Parsed all text exports and extracted PDF text: personal username/folder/file and URL tokens absent; duplicate review finding and redacted marker present. No installed app was modified.
- Independent review found case-sensitive URL removal and root `/` replacement could bypass privacy scrubbing. Both fixed, focused re-review clean, regression tests pass. Redaction remains best effort; names/versions/IDs and arbitrary diagnostics may still be sensitive. Local monitor history remains full.
- Developer URLs are user supplied or catalog supplied, never publisher verification. HTTPS addresses reject credentials/custom ports. Built-in/custom trust rules and update feeds are unchanged by manual URLs. Snapshot schema 1/2 compatibility retained through optional fields.
- Apache-2.0 official text added after user's explicit selection. NOTICE, separate brand terms, contribution/security/privacy docs, issue/PR templates, fictional sample and macOS CI workflow prepared. Workflow action majors checked against official action READMEs; GitHub CI has not run. No repository has been published. Private vulnerability reporting/contact must be configured before publication.
- Version 1.3.0 (5) Apple Silicon/macOS14.4+ local build remains ad-hoc signed. Release ZIP includes license/notice/brand/privacy text in app resources; SHA256SUMS generated. Final archive integrity/equality, extracted strict signature, executable permissions, version metadata, four bundled legal/privacy files and extracted-app redacted PDF export passed. ZIP SHA-256: `3c98a84c752bdc3701e976619858eb20e8cd91e64d6deae02eb1e37ce9a9ef46`.
- Native snapshot/report Save dialogs were not completed in this run; packaged CLI checked export engines end to end. Background schedule/notification activation remains untested and disabled.

---

# Xtracsys App Audit 1.2.1 branding verification — 2026-10-22

- Original supplied PNG preserved; app icon converted with aspect-preserving sizing and white backing. Native header, window title and About panel display Xtracsys identity. Rust accent, black artwork and warm-white report panels follow supplied references. Native semantic status colours retained.
- Native GUI launched with 232 apps; logo/header and About panel visually inspected. Policy invalid-team draft rejected and cancelled. Publisher registry displayed nine built-ins/zero custom. Monitor panel displayed Schedule disabled. No policy saved or schedule activated.
- All **40 tests passed, 0 failures** after final branding edits. Release build 1.2.1 (4) succeeded. Extracted ZIP strict ad-hoc signature, executable permissions, version/icon metadata, identical original logo resource and icon presence verified. Stable/versioned ZIPs match and pass archive integrity.
- Extracted app generated full 232-app PDF successfully. Branded first page rasterized and visually inspected: Xtracsys logo, rust headings and readable evidence without overlap. Offline HTML generated through packaged monitor runner; embedded PNG decoded and matched supplied original, CSP allows only data images. No remote branding dependency.
- Final ZIP SHA-256: `0585106f23e53b95ba4d0e9d59baee272254939e4f300b7ee0dde87df43904a8`.
- Remaining distribution work: Developer ID signing/notarization requires an appropriate Apple developer identity. Local build remains ad-hoc signed. Earlier limitations below remain unless superseded by this entry; the previously blocked settings-panel previews are now checked. Actual schedule activation/notification delivery and replacement PDF Save dialog remain untested.

---

# App Audit 1.2 verification — 2026-10-22

## Approved additions

| Improvement | Evidence |
| --- | --- |
| Integrity | Streaming SHA-256 known-vector/size-cap tests; same-version hash comparison/action finding; executable change in actual packaged headless fixture. Covers main executable, Info.plist and CodeResources, with unstable/unreadable evidence retained as unknown. |
| Findings | Severity/evidence/next-step engine tests; native Findings panel displayed three coverage unknowns and the selected inventory-warning details before the Mac locked. Strict signing/Gatekeeper disagreement is explained separately. |
| Daily audits/alerts | Daily LaunchAgent property list tested for time and separate arguments. Packaged command ran isolated fixture four times: quiet initial baseline, quiet repeat, two events on same-version executable change, quiet repeat. Integration tests preserve successful pointers on failure, compare against last complete audit across missing roots, retain known alert fingerprints through partial runs and distinguish same-named apps. No real LaunchAgent installed or OS notification sent. |
| Approved-app policy | Tests cover minimum-version violation, unknown version and invalid duplicate rules; validated local JSON and draft native editor compile. Policy defaults off. |
| Reports | HTML escaping/CSP test. Native PDF tests verify finite A4 output and oversized-block pagination. Full 232-app report generated through packaged --report-pdf: 59 A4 pages, 167,422 bytes; first/middle/last pages rasterized and visually inspected, readable and unclipped. |
| Publisher registry | Nine explicit built-in bundle/team/cask rules. Six added identities observed from Apple-anchored installed-app signatures; Homebrew tokens/artifacts checked. Tests reject invalid teams and built-in overrides. Native draft editor/import/export compile. |

## Final verification

**40 tests passed, 0 failures**, including all prior 27 tests and 13 new core/monitor/PDF tests:

```sh
CLANG_MODULE_CACHE_PATH=/tmp/appaudit-clang SWIFTPM_MODULECACHE_OVERRIDE=/tmp/appaudit-swift \
  swift test --disable-sandbox --build-system native --scratch-path /tmp/appaudit-build --package-path Projects/AppAudit
```

The release build produces version **1.2.0 (3)** for arm64, minimum macOS **14.4**. Versioned and stable ZIP integrity/equality, extracted executable permissions, bundle metadata and strict ad-hoc signature passed. Final ZIP: 676,511 bytes; SHA-256 `6e45e1fa436c93367f3d02a8fa688f99e6a702647f0bfc48dbd4be5da9d45119`. The extracted app also successfully generated the full PDF. No third-party runtime dependency added.

Independent source review found three monitoring defects (complete-baseline retention, partial-run dedup, app-specific alert identities); all fixed with regression coverage. PDF review found oversized-block pagination could fail at a nearly-full page; exporter now retries on a fresh page and has an oversized-text regression. No other important defect reported.

## Limits and unperformed checks

- The Mac locked during final UI QA. Findings was exercised before lock; final policy/registry/monitor editor interaction and the replacement PDF Save dialog were not exercised. Their source compiles; report engine and packaged CLI were checked end to end.
- LaunchAgent installation/removal and macOS notification permission/delivery were not activated in this run. Generated plist and runner logic are tested. Scheduling remains off until the user enables it.
- Initial WebKit printing produced runaway empty pages on this macOS build. Stopped own test app and replaced the print path with bounded CoreText/CoreGraphics generation (500-page cap and atomic output). Full replacement output was visually verified.
- Hashes cover three selected files rather than every bundle file. Signing, Gatekeeper, notarization, update availability and policy are separate evidence, not malware/CVE verdicts.
- Snapshot imports are unauthenticated history. Partial scans preserve the last complete monitoring baseline and suppress removal claims. At most 30 history entries are retained.
- Policy requires user-defined rules; custom publisher rules require independently trusted vendor evidence. Built-in verified update coverage remains deliberately limited to nine app identities.
- Receipt dates may describe updates; filesystem dates are estimates; Spotlight last-used can be Unknown. A standard inventory found 232 apps and two unreadable-bundle warnings on this Mac.
- Local build is ad-hoc signed, not Developer ID signed/notarized. Tested on Apple Silicon/macOS 27.0.1; older supported OS versions and Intel have not been runtime tested.
- Root/network sandbox restrictions can reduce CLI metadata visibility. DNS screening remains best effort. SwiftPM native backend works here but emits a deprecation warning.

---

# Prior 1.1 verification — 2026-10-22

## Requirements and evidence

| Approved improvement | Verification |
| --- | --- |
| Saved audits and comparison | Snapshot JSON round-trip, schema rejection, duplicate-path rejection and security/receipt preservation tests pass. Native Save dialog wrote 232 apps plus collected Chrome evidence. Opened a separate test baseline containing deliberate fixture differences; comparison UI showed Added TextEdit, Relocated Activity Monitor, Removed Historical Fixture and Updated Chrome, with scan-warning caveat. Real installed apps were not modified. |
| Historical evidence review/export | Saved audit evidence tab reopened Chrome publisher/team, Gatekeeper and notarization results. Saved CSV exported 232 rows and 25 columns; Python csv parser confirmed historical evidence. |
| Stronger update identity | Tests reject wrong bundle IDs, wrong signed IDs, wrong teams and invalid signatures. Live online command verified Code by bundle ID and valid Microsoft team; Chrome's failed strict resource check yielded Unverified candidate rather than Current. Unknown cask compatibility remains Unknown. Filename-only Cursor match remains explicitly unverified. |
| Security evidence | Native inspection displayed Google signing team/identity, separate strict signature failure, Gatekeeper Accepted and Confirmed by Gatekeeper notarization. Live Microsoft Teams inspection returned Valid, Accepted and confirmed notarization. Mach-O tests cover thin arm64, universal arm64/x86_64 and malformed headers. |
| Install evidence | Exact receipt parsing and payload-path tests pass. Live Microsoft AutoUpdate inspection matched com.microsoft.package.Microsoft_AutoUpdate.app, package version 4.85.26091737, receipt event 2026-09-19T02:11:58Z, with Valid signature and Accepted Gatekeeper. Primary/fallback receipt sources merge by ID and newest date; tests cover later events. Missing/time-out/error statuses remain separate from confirmed matches. |
| Remember preferences | UserDefaults tests cover folders/filter/search/sort/direction/column visibility round-trip and corrupt-data fallback. Native relaunch restored Chrome search, version sort order and visible security columns; then test search/sort were reset to full inventory by name. |

## Automated checks

**27 tests passed, 0 failures.** Command from the workspace root:

```sh
CLANG_MODULE_CACHE_PATH=/tmp/appaudit-clang SWIFTPM_MODULECACHE_OVERRIDE=/tmp/appaudit-swift \
  swift test --disable-sandbox --build-system native --scratch-path /tmp/appaudit-build --package-path Projects/AppAudit
```

Tests also cover numeric/incomparable versions, nested helper exclusion, missing marketing versions, missing-folder warnings, CSV escaping/formula prefixes, Sparkle build/marketing parsing and OS bounds, malformed XML, cask object/rename/ambiguity/OS variants, URL restrictions, DNS completion races, command output and timeout termination, scope notes, duplicate bundle IDs and path replacement.

`scripts/build.sh` succeeds, produces a **1.1.0** arm64 app with minimum macOS **14.4**, verifies its ad-hoc signature and creates versioned/stable ZIPs. Extracted the versioned ZIP with ditto; verified executable permissions and `codesign --verify --strict` on the extracted app. ZIP integrity, excluded AppleDouble sidecars, bundle metadata and equality of both ZIP names checked.

## Review

Independent source review completed. Fixed missing scan-root warnings, exposed saved evidence in-app, retained receipt lookup failure provenance, and corrected merging receipt sources before choosing latest event. Exact receipt-payload fallback was separately reviewed. No remaining important defect reported after those corrections; final merge correction has passing regression coverage.

## Scope and remaining limits

- Standard scan on this Mac: 232 apps, 42 Spotlight last-use dates, 190 unknown; two unreadable-bundle warnings (Suno and liquiddetectiond). Unknown is not never used.
- Receipt dates are installer events, possibly updates, not proof of original installation. Absent receipt evidence falls back to filesystem creation estimates.
- Explicit verified cask rules currently cover Chrome, Visual Studio Code and Firefox. Other matches remain candidates. Source compatibility data can be unsupported; no universal update coverage is claimed.
- Security evidence is collected on request. Stop skips remaining apps after the current bounded inspection; a full audit can take time. No inspected application or downloaded installer is executed.
- Imported snapshots are unauthenticated saved observations. Comparison detects identity/version/build/path changes, not all same-version binary modifications. Changed scopes and missing roots are flagged.
- Settings persist column-group visibility, not user-resized widths/order. Baselines are selected explicitly each session.
- The local app is ad-hoc signed, not Developer ID signed/notarized. Tested on this Apple Silicon Mac/macOS 27; macOS 14.4–26 and Intel have not been runtime tested.
- SwiftPM emits cache-permission and deprecated-native-engine warnings in this sandbox. Default Swift Build engine cannot write its external-volume manifest; the documented native engine works.
- Network DNS screening remains best effort rather than connection pinning. Signature checks, Gatekeeper and notarization are separate evidence, not malware/CVE verdicts.

### 1.4.2 notarization clarification

61 Swift tests pass, including accepted source parsing, failure/timeout precedence, misleading diagnostic text, and backward-compatible optional column preferences. Native Swift build compiles the updated UI. Existing snapshot evidence is preserved. Live Gatekeeper responses vary by macOS version; unrecognized sources intentionally remain inconclusive.

### 1.4.3 exception review queue

62 Swift tests pass. Added deterministic coverage for exact expiry, the inclusive 30-day window, no expiry, changed evidence, absent findings, and revocation precedence. Native compilation checks the queue UI and renewal sheet. UI interaction has not been exercised against the active user audit; that audit remains open.

### 1.5.0 filesystem-wide app discovery

67 Swift tests pass. Red/green reproduction demonstrated the old scanner missed hidden apps, nested apps and bundle-contained apps. New tests verify hidden/nested discovery, linked directories, cycle/duplicate protection, `.app` symlink targets without an app extension, default scope and legacy preference migration, early/late cancellation warnings, FIFO rejection, oversized metadata rejection and bounded executable-header reads. Independent static review identified special-file and late-cancellation defects; both were corrected and re-reviewed with no remaining important findings. Device filesystem `/dev` is explicitly excluded and reported. Native UI compilation is checked; a full live filesystem scan and interaction with the user’s active audit were not performed. Full Disk Access and real protected-volume coverage have not been verified. Stop is cooperative; a stalled filesystem or Spotlight call can delay completion.

## Column sorting fix — 2026-10-23

All inventory headers now declare sort keys, including Update, Update age, Architecture, Signature, Publisher, Gatekeeper and optional Notarization. Live presentation rows use the displayed update/security values and receipt-aware install dates. Update age uses evidence dates (unknown first and OS-maintained last in ascending order); ties use application path. New sort columns and direction persist through the existing preferences flow. Full Swift suite: 69 tests passed, including both directions for evidence, architecture and age keys. Native executable compiled with the table bindings. Interactive header clicking has not been verified in this session.

Follow-up live verification: the existing process had started before the rebuild and retained the old executable despite its bundle being replaced. Fully quit and relaunched the dist bundle; confirmed new process start. Native header actions reordered Update age rows and Architecture rows in both directions (descending began with x86_64). Restored empty search and restarted full inventory scan after pausing startup scan for the checks. Security columns contained identical Not checked values in this session.

## 1.5.1 release preparation — 2026-10-23

- Version 1.5.1 / build 11; 69 Swift tests passed with zero failures.
- Production build completed. Extracted ZIP strict ad-hoc signature verified; Info.plist version/build, executable permission and ZIP integrity checked. No AppleDouble files in binary archive.
- Public source uses the standalone project allowlist; generated build/export/temp directories and enclosing workspace are excluded. Text reviewed for local owner paths and common credential patterns; no matches found. This is a focused publication review, not a formal security audit.
- Both versioned ZIPs are covered by SHA256SUMS. Clean GitHub import folder is prepared from the source archive, including hidden workflow and ignore files.
- Release documents describe Apple Silicon/macOS 14.4+, per-machine settings and full quit before updates. CI includes source packaging and both release downloads.
- Second-Mac testing, first GitHub CI run, remote repository setup/publication and Developer ID signing/notarization remain outstanding. Current binary is ad-hoc signed only. Previous live sorting verification applies to the unchanged sorting implementation.
