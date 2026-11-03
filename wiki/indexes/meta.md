# Meta
*repository workflow*

- **Package.swift** — `Package.swift` (3 lines): Declares the macOS 14.4 minimum, the AppAudit executable, the AuditCore library target, the copied Xtracsys logo resource, and the XCTest target.
- **.gitignore** — `.gitignore` (9 lines): Keeps Swift build products, generated distribution artifacts, temporary reports, and private plan notes out of source control.
- **bug_report.yml** — `.github/ISSUE_TEMPLATE/bug_report.yml` (26 lines): Prompts reporters for reproducible problem details while warning them not to include private inventory data.
- **feature_request.md** — `.github/ISSUE_TEMPLATE/feature_request.md` (10 lines): Asks for a concrete workflow improvement and the reason it would help.
- **PULL_REQUEST_TEMPLATE.md** — `.github/PULL_REQUEST_TEMPLATE.md` (9 lines): Gives contributors a short checklist for describing the change and its verification.
- **macos.yml** — `.github/workflows/macos.yml` (31 lines): Runs the Swift test suite and source-packager checks on supported macOS runners for pushes, pull requests, and manual dispatches.
- **build.sh** — `scripts/build.sh` (66 lines): Builds the Swift package, assembles the App bundle and release ZIP names, applies the configured signing mode, and regenerates checksums for local distribution.
- **package-source.py** — `scripts/package-source.py` (44 lines): Uses an explicit allowlist for source, tests, docs, GitHub templates, and examples; filters private plan notes and AppleDouble files; refuses symlinks; then creates the source ZIP and checksums.
