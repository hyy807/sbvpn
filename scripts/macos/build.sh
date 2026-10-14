#!/bin/bash
# Official source only: no Swift patches, entitlement fallbacks, or fake signatures.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
mkdir -p output/logs
exec > >(tee output/logs/build.log) 2>&1
[[ "$(uname -s)" == Darwin ]] || { echo 'macOS/Xcode required'; exit 1; }
# Assert actual source content rather than treating a declared revision as evidence.
python3 - <<'PY'
import subprocess
pins = {
    'Makefile': '274323492752448d66f96edffe6374f518ae1782',
    'HelperService/RootHelperService.swift': 'aaddf49c4586092c2d29dd797be88821608c822a',
    'sing-box.xcodeproj/project.pbxproj': 'f0cbe727d2557e83ce6e92586798929e7444a694',
    'sing-box.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved': '0abf72d9d8af03066efed510dca4dd9fad2aba82',
}
for path, expected in pins.items():
    actual = subprocess.check_output(['git', 'hash-object', 'clients/apple/' + path], text=True).strip()
    assert actual == expected, (path, expected, actual)
    print('official source blob:', path, actual)
PY
xcodebuild -version
go version
# These commands/tags are the official core's Apple build path.
make lib_install
export PATH="$PATH:$(go env GOPATH)/bin"
go run ./cmd/internal/build_libbox -target apple -platform macos
rm -rf clients/apple/Libbox.xcframework
ditto Libbox.xcframework clients/apple/Libbox.xcframework
python3 - <<'PY'
import plistlib
from pathlib import Path
p = Path('clients/apple/Libbox.xcframework')
d = plistlib.loads((p / 'Info.plist').read_bytes())
arches = {a for lib in d['AvailableLibraries'] if lib['SupportedPlatform'] == 'macos' for a in lib['SupportedArchitectures']}
assert arches == {'arm64', 'x86_64'}, arches
print('Libbox macOS architectures:', sorted(arches))
PY
cd clients/apple
# Resolve strictly from the official committed lock, never update moving packages.
xcodebuild -resolvePackageDependencies -project sing-box.xcodeproj -scheme SFM.System \
  -onlyUsePackageVersionsFromResolvedFile \
  -clonedSourcePackagesDirPath "$RUNNER_TEMP/SourcePackages"
# Exact official universal archive command, retaining raw output instead of xcbeautify.
xcodebuild archive -project sing-box.xcodeproj -scheme SFM.System \
  -configuration Release -archivePath build/SFM.System-universal.xcarchive \
  -derivedDataPath build/SFM.System-universal.dd \
  -skipPackagePluginValidation -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile \
  -clonedSourcePackagesDirPath "$RUNNER_TEMP/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  2>&1 | tee "$ROOT/output/logs/xcodebuild.log"
APP="$PWD/build/SFM.System-universal.xcarchive/Products/Applications/SFM.app"
python3 "$ROOT/scripts/macos/verify_bundle.py" "$APP" > "$ROOT/output/bundle-manifest.json"
# Upstream PKG layout/distribution/resources, without its unavailable --sign option.
mkdir -p build/pkgroot-universal
ditto "$APP" build/pkgroot-universal/SFM.app
pkgbuild --root build/pkgroot-universal \
  --component-plist SFM.System/component.plist \
  --identifier io.nekohasekai.sfamt.standalone --install-location /Applications \
  --min-os-version 13.0 --compression latest build/component-universal.pkg
productbuild --distribution SFM.System/distribution-universal.xml \
  --package-path build --resources SFM.System/Resources \
  "$ROOT/output/SFM-sbvpn-Universal-unsigned.pkg"
# Read back actual package payload, not only its outer file existence.
EXPANDED="$RUNNER_TEMP/sbvpn-pkg-expanded"
pkgutil --expand-full "$ROOT/output/SFM-sbvpn-Universal-unsigned.pkg" "$EXPANDED"
python3 - "$EXPANDED" "$ROOT/output/package-manifest.json" "$ROOT/scripts/macos/verify_bundle.py" <<'PY'
import pathlib, subprocess, sys
apps = list(pathlib.Path(sys.argv[1]).rglob('SFM.app'))
assert len(apps) == 1, apps
with open(sys.argv[2], 'w') as output:
    subprocess.run([sys.executable, sys.argv[3], str(apps[0])], stdout=output, check=True)
PY
cd "$ROOT/output"
shasum -a 256 *.pkg > SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS.txt
