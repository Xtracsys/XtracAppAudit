# Contributing

Use this directory as the root of the standalone App Audit repository. Open an issue explaining a concrete problem before proposing broad features. For bug fixes, include a focused regression test where practical.

## Build and test

Requires macOS 14.4+, Xcode command-line tools and Swift 6+. Run `./scripts/build.sh` for the native app and ZIP. Run `swift test --disable-sandbox --scratch-path /tmp/appaudit-tests` for the test suite.

Use temporary fixture bundles, never modify installed apps to test a defect. Keep scanning/inspection read-only; preserve distinctions between verified, candidate, unknown and unavailable evidence. A developer URL never establishes publisher trust. Do not execute inspected binaries or add automatic installers.

## Pull requests

Describe the user-visible problem, change and relevant verification. Keep changes focused. Network checks and signing observations must use fixtures in automated tests. Publisher-rule proposals need bundle ID, Apple team ID, cask token and independent vendor provenance; a filename match alone is insufficient.

Do not attach real inventories or unreviewed logs. Use fictional fixtures or the redacted export option, then review the result manually. Contributions are submitted under Apache-2.0; see LICENSE. Xtracsys artwork has separate terms in BRAND_TERMS.md.

For project or contribution questions, contact josh@xtracsys.com.
