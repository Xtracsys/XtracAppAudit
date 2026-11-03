# Publish the standalone GitHub repository

Use only the prepared AppAudit source folder as the repository root, never the enclosing multi-project workspace. The source ZIP contains this same standalone folder, including hidden .github and .gitignore files and the offline project wiki in `wiki/`. Generated binaries, real exports, user settings and build directories are excluded.

## Prepared locally

- Version 1.5.1 / build 11, with the inventory sorting fix.
- Apache-2.0 LICENSE and NOTICE; artwork permissions remain separately defined in BRAND_TERMS.md.
- README, CONTRIBUTING, SECURITY, PRIVACY, issue/PR templates and macOS CI.
- LAN installation guide, release notes and source/binary ZIPs with checksums.

## Suggested owner steps

1. For a binary release, test the app on another Apple Silicon Mac running macOS 14.4+ and follow INSTALL.md. This helps validate the recipient experience; it is not required to publish the source repository.
2. Create an **empty public repository named `XtracAppAudit`** under the Xtracsys account. The root `LICENSE` already applies Apache-2.0; do not initialize a README, license or .gitignore because those are supplied locally. A GitHub repository is the project container, not a subdirectory of another repository.
3. Open Terminal in the prepared AppAudit folder and run the commands below. Replace the remote placeholder with the exact clone URL from your new repository. Authenticate using your existing GitHub setup; do not embed a token in the URL.

```sh
git init -b main
git add .
git diff --cached --stat
git diff --cached --check
git commit -m "Prepare App Audit 1.5.1 open-source release"
git remote add origin YOUR_REPOSITORY_CLONE_URL
git push -u origin main
```

Before committing, review the staged files. Configure your chosen author name and the designated `opensource@xtracsys.com` email. Do not commit dist, output, tmp, `.archify`, `.build` or real inventories. Keep the clean folder as the standalone checkout for future changes; changes made in the original workspace are not synchronized automatically.

4. After the first push, review the **macOS checks** result. The workflow has been prepared and locally inspected, but no remote run exists yet. It tests, builds and verifies the archive/signature/checksums. Its app artifact is ad-hoc signed and not notarized. Branch rules can require this check after it has run successfully; a remote CI run is not required to upload or make the source repository public.
5. The maintainer contact is **opensource@xtracsys.com**. Researchers can send reports there privately. GitHub Private Vulnerability Reporting is an optional way to accept structured reports; it is not a repository publication prerequisite. Review artwork terms as owner.
6. For a binary release, complete any desired second-Mac acceptance check and use GitHub **Releases → Draft a new release**. Create tag `v1.5.1` against the intended main commit. Use docs/RELEASE_NOTES_1.5.1.md as the description and attach the two versioned ZIPs and SHA256SUMS. Publish when the draft is correct. Do not attach the entire workspace or a real audit export. Avoid mixing locally generated checksums with different CI-built archives. The source repository may be published independently of a binary release.

GitHub Desktop is an alternative to the Terminal steps: create a local repository from the prepared folder, commit, and publish. If you already created the remote repository, connect to its exact URL rather than creating a second repository.

## Developer ID signing and notarization

Public source publication does not require an Apple Developer account. Smoother binary installation requires the owner's Developer ID Application identity and Apple notarization credentials. The current build script deliberately uses ad-hoc signing; it must be adapted before creating a notarized release.

The signed release sequence is: build → Developer ID sign with hardened runtime and secure timestamp → verify signature → submit an archive with `xcrun notarytool` → confirm acceptance → staple and validate the app ticket → recreate the final ZIP → verify its extracted app and Gatekeeper assessment → regenerate checksums. Keep certificates/private keys and notarization credentials in Keychain or protected CI secrets, never in source. No signing identity or account has been invented, and no notarization has been performed.

Apple: https://developer.apple.com/developer-id/
GitHub import guide: https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github
