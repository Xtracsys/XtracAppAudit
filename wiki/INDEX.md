# Xtracsys App Audit Wiki — Wiki Index

> Updated 2026-11-02 · 66 documented files · data: `wiki_data.json`

## Open the wiki

Open `index.html` in a browser. The page works offline.

## Tabs

- **Overview** — product scope and operating boundaries.
- **User Guide** — task-based instructions and interactive workflow diagrams.
- **Release Readiness** — release review findings, verification ledger, and functional requirements.
- **File System** — documented project files grouped by folder.

## Update the wiki

1. Edit `wiki_data.json`, the canonical content file. Guide and overview tabs live in `tabs`; file records live inside the File System tab's `files` list.
2. Keep each file record's `category` set to `specs`, `core`, `tests`, or `meta`.
3. Run `python3 wiki/build.py` from the project root. It refreshes source facts, the File System tables, overview counts, Markdown indexes, and embedded HTML.

## Files

### Specifications
*foundation documents*

| # | file | path | lines | status |
|---|---------|------|-------|--------|
| 01 | README.md | `README.md` | 198 | SPEC |
| 02 | LICENSE | `LICENSE` | 202 | SPEC |
| 03 | NOTICE | `NOTICE` | 5 | SPEC |
| 04 | BRAND_TERMS.md | `BRAND_TERMS.md` | 9 | SPEC |
| 05 | CHANGELOG.md | `CHANGELOG.md` | 12 | SPEC |
| 06 | CONTRIBUTING.md | `CONTRIBUTING.md` | 17 | SPEC |
| 07 | SECURITY.md | `SECURITY.md` | 9 | SPEC |
| 08 | PRIVACY.md | `PRIVACY.md` | 19 | SPEC |
| 09 | VERIFICATION.md | `VERIFICATION.md` | 161 | SPEC |
| 10 | AppIcon.icns | `Branding/AppIcon.icns` | — | SPEC |
| 11 | README.md | `Branding/README.md` | 7 | SPEC |
| 12 | GITHUB_RELEASE.md | `docs/GITHUB_RELEASE.md` | 43 | SPEC |
| 13 | INSTALL.md | `docs/INSTALL.md` | 20 | SPEC |
| 14 | RELEASE_NOTES_1.5.1.md | `docs/RELEASE_NOTES_1.5.1.md` | 23 | SPEC |
| 15 | fictional-audit.json | `examples/fictional-audit.json` | 54 | SAMPLE |

### Core
*app and audit engine*

| # | file | path | lines | status |
|---|---------|------|-------|--------|
| 01 | AppAudit.swift | `Sources/AppAudit/AppAudit.swift` | 99 | CORE |
| 02 | AuditModel.swift | `Sources/AppAudit/AuditModel.swift` | 324 | CORE |
| 03 | AuditWorkflowViews.swift | `Sources/AppAudit/AuditWorkflowViews.swift` | 107 | CORE |
| 04 | ComparisonView.swift | `Sources/AppAudit/ComparisonView.swift` | 34 | CORE |
| 05 | ContentView.swift | `Sources/AppAudit/ContentView.swift` | 379 | CORE |
| 06 | DeveloperLinksView.swift | `Sources/AppAudit/DeveloperLinksView.swift` | 59 | CORE |
| 07 | FindingsView.swift | `Sources/AppAudit/FindingsView.swift` | 43 | CORE |
| 08 | MonitorView.swift | `Sources/AppAudit/MonitorView.swift` | 40 | CORE |
| 09 | NativeMonitor.swift | `Sources/AppAudit/NativeMonitor.swift` | 82 | CORE |
| 10 | PDFExporter.swift | `Sources/AppAudit/PDFExporter.swift` | 15 | CORE |
| 11 | PolicyViews.swift | `Sources/AppAudit/PolicyViews.swift` | 107 | CORE |
| 12 | SavedAuditView.swift | `Sources/AppAudit/SavedAuditView.swift` | 49 | CORE |
| 13 | AppClassification.swift | `Sources/AuditCore/AppClassification.swift` | 51 | CORE |
| 14 | AuditTableRow.swift | `Sources/AuditCore/AuditTableRow.swift` | 30 | CORE |
| 15 | AuditWorkflow.swift | `Sources/AuditCore/AuditWorkflow.swift` | 96 | CORE |
| 16 | Brand.swift | `Sources/AuditCore/Brand.swift` | 14 | CORE |
| 17 | XtracsysLogo.png | `Sources/AuditCore/Resources/XtracsysLogo.png` | — | CORE |
| 18 | DeveloperLinks.swift | `Sources/AuditCore/DeveloperLinks.swift` | 35 | CORE |
| 19 | Evidence.swift | `Sources/AuditCore/Evidence.swift` | 212 | CORE |
| 20 | Findings.swift | `Sources/AuditCore/Findings.swift` | 87 | CORE |
| 21 | Integrity.swift | `Sources/AuditCore/Integrity.swift` | 43 | CORE |
| 22 | Inventory.swift | `Sources/AuditCore/Inventory.swift` | 193 | CORE |
| 23 | Monitoring.swift | `Sources/AuditCore/Monitoring.swift` | 186 | CORE |
| 24 | PDFReport.swift | `Sources/AuditCore/PDFReport.swift` | 111 | CORE |
| 25 | Policy.swift | `Sources/AuditCore/Policy.swift` | 81 | CORE |
| 26 | Preferences.swift | `Sources/AuditCore/Preferences.swift` | 39 | CORE |
| 27 | ProcessRunner.swift | `Sources/AuditCore/ProcessRunner.swift` | 47 | CORE |
| 28 | Reports.swift | `Sources/AuditCore/Reports.swift` | 41 | CORE |
| 29 | ShareExport.swift | `Sources/AuditCore/ShareExport.swift` | 56 | CORE |
| 30 | Snapshots.swift | `Sources/AuditCore/Snapshots.swift` | 117 | CORE |
| 31 | Updates.swift | `Sources/AuditCore/Updates.swift` | 311 | CORE |
| 32 | NetworkDeviceDiscovery.swift | `Sources/AuditCore/NetworkDeviceDiscovery.swift` | 141 | CORE |
| 33 | NetworkDevicesView.swift | `Sources/AppAudit/NetworkDevicesView.swift` | 81 | CORE |
| 34 | VisibleAppExport.swift | `Sources/AuditCore/VisibleAppExport.swift` | 53 | CORE |

### Tests
*verification*

| # | file | path | lines | status |
|---|---------|------|-------|--------|
| 01 | AuditUpgradeTests.swift | `Tests/AuditCoreTests/AuditUpgradeTests.swift` | 125 | TEST |
| 02 | CommunityTests.swift | `Tests/AuditCoreTests/CommunityTests.swift` | 57 | TEST |
| 03 | CoreTests.swift | `Tests/AuditCoreTests/CoreTests.swift` | 174 | TEST |
| 04 | MonitoringTests.swift | `Tests/AuditCoreTests/MonitoringTests.swift` | 178 | TEST |
| 05 | NotarizationTests.swift | `Tests/AuditCoreTests/NotarizationTests.swift` | 24 | TEST |
| 06 | RoutingTests.swift | `Tests/AuditCoreTests/RoutingTests.swift` | 66 | TEST |
| 07 | TableRowTests.swift | `Tests/AuditCoreTests/TableRowTests.swift` | 29 | TEST |
| 08 | WorkflowTests.swift | `Tests/AuditCoreTests/WorkflowTests.swift` | 118 | TEST |
| 09 | test_package_source.py | `Tests/test_package_source.py` | 86 | TEST |

### Meta
*repository workflow*

| # | file | path | lines | status |
|---|---------|------|-------|--------|
| 01 | Package.swift | `Package.swift` | 3 | META |
| 02 | .gitignore | `.gitignore` | 9 | META |
| 03 | bug_report.yml | `.github/ISSUE_TEMPLATE/bug_report.yml` | 26 | META |
| 04 | feature_request.md | `.github/ISSUE_TEMPLATE/feature_request.md` | 10 | META |
| 05 | PULL_REQUEST_TEMPLATE.md | `.github/PULL_REQUEST_TEMPLATE.md` | 9 | META |
| 06 | macos.yml | `.github/workflows/macos.yml` | 31 | META |
| 07 | build.sh | `scripts/build.sh` | 66 | META |
| 08 | package-source.py | `scripts/package-source.py` | 44 | META |
