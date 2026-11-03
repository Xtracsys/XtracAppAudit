#!/usr/bin/env python3
"""Package only the standalone project's source and public documentation."""
from pathlib import Path
import zipfile
root = Path(__file__).resolve().parent.parent
out = root / 'dist' / 'App-Audit-1.5.1-source.zip'
allowed = ['Package.swift', 'README.md', 'LICENSE', 'NOTICE', 'BRAND_TERMS.md',
           'CHANGELOG.md', 'CONTRIBUTING.md', 'SECURITY.md', 'PRIVACY.md', 'VERIFICATION.md',
           '.gitignore', '.github', 'Sources', 'Tests', 'Branding', 'scripts', 'docs', 'examples', 'wiki']
package_files = []
for name in allowed:
    entry = root / name
    if entry.is_symlink():
        raise SystemExit(f'Refusing source package symlink: {entry.relative_to(root)}')
    if not entry.exists():
        continue
    files = sorted(entry.rglob('*')) if entry.is_dir() else [entry]
    for file in files:
        if file.is_symlink():
            raise SystemExit(f'Refusing source package symlink: {file.relative_to(root)}')
        if file.relative_to(root).parts[:2] == ('docs', 'superpowers'):
            continue
        if file.parent == root / 'docs' and file.name.endswith('-plan.md'):
            continue
        if file.is_file() and not file.name.startswith('._') and file.name != '.DS_Store' and '__pycache__' not in file.parts:
            package_files.append(file)

out.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as archive:
    for file in package_files:
        info = zipfile.ZipInfo.from_file(file, Path('AppAudit') / file.relative_to(root))
        if file.parent == root / 'scripts' and file.suffix in {'.sh', '.py'}:
            info.external_attr = (0o100755 << 16)
        archive.writestr(info, file.read_bytes(), compress_type=zipfile.ZIP_DEFLATED)
print(out)

# Match the two versioned release downloads; run build.sh before this script.
import hashlib
binary = root / 'dist' / 'App-Audit-1.5.1-macOS-arm64.zip'
if not binary.is_file():
    raise SystemExit('Run scripts/build.sh before packaging source/checksums.')
(root / 'dist' / 'SHA256SUMS').write_text(''.join(
    hashlib.sha256(file.read_bytes()).hexdigest() + '  ' + file.name + '\n'
    for file in (binary, out)))
