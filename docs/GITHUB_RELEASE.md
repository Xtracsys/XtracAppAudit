# Publish and maintain the standalone GitHub repository

**Current repository:** [Xtracsys/XtracAppAudit](https://github.com/Xtracsys/XtracAppAudit), public, Apache-2.0. The initial `main` commit (`f709839`) was published on 2026-11-02. No release tag or binary release has been published.

The first GitHub Actions run failed because Git recorded `scripts/build.sh` without its executable bit. Commit `7d953c3` corrects the mode to `100755`; [run #2 passed](https://github.com/Xtracsys/XtracAppAudit/actions/runs/41583360704), including tests, source packaging, app build, archive/signature verification and artifact upload. Future pushes run the same [macOS checks](https://github.com/Xtracsys/XtracAppAudit/actions/workflows/macos.yml).

Use only the prepared AppAudit source folder as the repository root, never the enclosing multi-project workspace. The source ZIP contains this same standalone folder, including hidden .github and .gitignore files and the offline project wiki in `wiki/`. Generated binaries, real exports, user settings and build directories are excluded.

## Prepared locally

- Version 1.5.1 / build 11, with the inventory sorting fix.
- Apache-2.0 LICENSE and NOTICE; artwork permissions remain separately defined in BRAND_TERMS.md.
- README, CONTRIBUTING, SECURITY, PRIVACY, issue/PR templates and macOS CI.
- LAN installation guide, release notes and source/binary ZIPs with checksums.

## Maintainer steps

1. For a binary release, test the app on another Apple Silicon Mac running macOS 14.4+ and follow INSTALL.md. This helps validate the recipient experience; it is not required to publish the source repository.
2. The public repository is already created with the existing root `LICENSE` and `.gitignore`; do not create a second repository or initialize replacement files. The AppAudit directory is the repository root, not a subdirectory of the enclosing multi-project workspace.
3. For future source changes, work in this standalone checkout and push to its existing `origin` remote. Review staged files before committing:

```sh
git status --short
git add -A
git diff --cached --stat
git diff --cached --check
git commit -m "Describe the change"
git push origin main
```

Configure your chosen author name and the designated `opensource@xtracsys.com` email. Do not commit dist, output, tmp, `.archify`, `.build` or real inventories. Keep this folder as the standalone checkout for future changes; changes made in the enclosing workspace are not synchronized automatically.

4. Review the **macOS checks** result after each push. The workflow tests, builds and verifies the archive/signature/checksums. Its app artifact is ad-hoc signed and not notarized. Branch rules can require this check after it runs successfully; branch protection is optional.
5. The maintainer contact is **opensource@xtracsys.com**. Researchers can send reports there privately. GitHub Private Vulnerability Reporting is an optional way to accept structured reports; it is not a repository publication prerequisite. Review artwork terms as owner.
6. For a binary release, complete any desired second-Mac acceptance check and use GitHub **Releases → Draft a new release**. Create tag `v1.5.1` against the intended main commit. Use docs/RELEASE_NOTES_1.5.1.md as the description and attach the two versioned ZIPs and SHA256SUMS. Publish when the draft is correct. Do not attach the entire workspace or a real audit export. Avoid mixing locally generated checksums with different CI-built archives. The source repository may be published independently of a binary release.

For GitHub Desktop updates, open this existing `XtracAppAudit` repository, commit the reviewed changes, then choose **Push origin**. The remote is already configured; do not create a second repository. For a fresh clone, use `https://github.com/Xtracsys/XtracAppAudit.git`.

## Developer ID signing and notarization

Public source publication does not require an Apple Developer account. Smoother binary installation requires the owner's Developer ID Application identity and Apple notarization credentials. The current build script deliberately uses ad-hoc signing; it must be adapted before creating a notarized release.

The signed release sequence is: build → Developer ID sign with hardened runtime and secure timestamp → verify signature → submit an archive with `xcrun notarytool` → confirm acceptance → staple and validate the app ticket → recreate the final ZIP → verify its extracted app and Gatekeeper assessment → regenerate checksums. Keep certificates/private keys and notarization credentials in Keychain or protected CI secrets, never in source. No signing identity or account has been invented, and no notarization has been performed.

Apple: https://developer.apple.com/developer-id/
GitHub import guide: https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github
