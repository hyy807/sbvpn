# sbvpn — sing-box core with official four-platform clients

This repository is a self-contained source tree for the current sbvpn core and the
unmodified official SagerNet GUI clients required to build iOS, macOS, Android and
Windows packages. The core keeps this repository's private Lightning protocol support;
the client trees are vendored from fixed upstream commits and are not patched to add
features or bypass platform security.

## Source layout

- Core: repository root (`github.com/sagernet/sing-box` plus the current sbvpn protocol changes).
- iOS: `clients/apple-ios`, the exact Apple source compiled by successful run
  `38549055133`: official `SagerNet/sing-box-for-apple` commit
  `56681841de346fb2185dc6eceba415f6b41bb2b2`, including Runestone. The historical
  workflow checked out a local fork first, then explicitly switched to this official
  `dev` commit before patching and compiling.
- macOS: `clients/apple`, upstream `SagerNet/sing-box-for-apple` commit
  `56681841de346fb2185dc6eceba415f6b41bb2b2`, including Runestone.
- Android: `clients/android`, upstream `SagerNet/sing-box-for-android` commit
  `bc73504fcb858400a939140ad785ed92f4c9f429`.
- Windows: `clients/desktop`, upstream `SagerNet/sing-box-for-desktop` commit
  `2c3ba5cabfe039d4f46561218cfb3a2934e40d29`, including dashboard dependencies.

Each client directory has a `.upstream-commit` file. Client sources are ordinary tracked
files, not submodules, so a single checkout contains everything required by the four
build workflows.

## Four build workflows

- `.github/workflows/ipa.yml`: restored pre-four-platform SFI source and build settings → unsigned IPA.
- `.github/workflows/macos.yml`: official standalone SFM.System target → universal staging PKG.
- `.github/workflows/apk.yml`: official `other` and `otherLegacy` targets → ten installable debug-signed APKs.
- `.github/workflows/windows.yml`: official Electron desktop target → one x64 NSIS installer `.exe`.

The workflows compile libbox/boxdd from the core in this repository. They do not download
a replacement core or a moving client branch.

## Signing reality

- iOS requires matching provisioning profiles that grant App Groups, NetworkExtension and
  every embedded extension's capabilities. The unsigned IPA is staging input for proper signing.
- macOS VPN/system-extension operation requires matching Developer ID identities, restricted
  entitlements and notarization. The unsigned PKG is staging input, not a working distribution.
- Android debug signing is installable and keeps all client features, but is not SagerNet's release key.
- Windows uses an ephemeral self-signed Authenticode certificate consistently across the
  official GUI, worker and daemon. This preserves the official signer-matching security logic;
  Windows displays an unknown-publisher warning because that certificate is not publicly trusted.

## Upstream documentation

https://sing-box.sagernet.org

## License

```
Copyright (C) 2022 by nekohasekai <contact-sagernet@sekai.icu>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <http://www.gnu.org/licenses/>.

In addition, no derivative work may use the name or imply association
with this application without prior consent.
```