#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/appaudit-clang"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/appaudit-swift"
scratch="${TMPDIR:-/tmp}/appaudit-release"
swift build --arch arm64 --disable-sandbox --scratch-path "$scratch" -c release
bin_dir=$(swift build --arch arm64 --disable-sandbox --scratch-path "$scratch" -c release --show-bin-path)
app="dist/App Audit.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
COPYFILE_DISABLE=1 cp "$bin_dir/AppAudit" "$app/Contents/MacOS/AppAudit"
COPYFILE_DISABLE=1 cp Sources/AuditCore/Resources/XtracsysLogo.png "$app/Contents/Resources/XtracsysLogo.png"
COPYFILE_DISABLE=1 cp Branding/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
COPYFILE_DISABLE=1 cp LICENSE NOTICE BRAND_TERMS.md PRIVACY.md "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AppAudit</string>
<key>CFBundleIdentifier</key><string>com.xtracsys.appaudit</string>
<key>CFBundleName</key><string>App Audit</string>
<key>CFBundleDisplayName</key><string>App Audit</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.5.1</string>
<key>CFBundleVersion</key><string>11</string>
<key>LSMinimumSystemVersion</key><string>14.4</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSLocalNetworkUsageDescription</key><string>App Audit looks for devices advertising supported Bonjour services on your local network only when Find network devices is on.</string>
<key>NSBonjourServices</key><array>
<string>_workstation._tcp</string>
<string>_device-info._tcp</string>
<string>_ssh._tcp</string>
<string>_smb._tcp</string>
<string>_ipp._tcp</string>
<string>_ipps._tcp</string>
<string>_printer._tcp</string>
<string>_airplay._tcp</string>
<string>_raop._tcp</string>
<string>_googlecast._tcp</string>
</array>
</dict></plist>
PLIST
python3 - "$app" <<'PYTHON'
import pathlib, sys
for sidecar in pathlib.Path(sys.argv[1]).rglob('._*'):
    sidecar.unlink()
PYTHON
codesign --force --sign - "$app"
codesign --verify --strict "$app"
echo "Built: $(pwd)/$app"
python3 - <<'PYTHON'
from pathlib import Path
import zipfile, shutil
root = Path('dist')
archive = root / 'App-Audit-1.5.1-macOS-arm64.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as output:
    for file in (root / 'App Audit.app').rglob('*'):
        if file.is_file() and not file.name.startswith('._'):
            output.write(file, file.relative_to(root))
shutil.copyfile(archive, root / 'App-Audit-macOS-arm64.zip')
print('Packaged:', archive.resolve())
import hashlib
(root / 'SHA256SUMS').write_text(hashlib.sha256(archive.read_bytes()).hexdigest() + '  ' + archive.name + '\n')
PYTHON
