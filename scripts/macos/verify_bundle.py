#!/usr/bin/env python3
"""Read a real SFM.System bundle; fail on missing GUI/extension/helper/slices."""
import json
import plistlib
import subprocess
import sys
from pathlib import Path


def verify(app):
    app = Path(app)
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'io.nekohasekai.sfamt.standalone', info
    extensions = list((app / 'Contents/Library/SystemExtensions').glob('*.systemextension'))
    assert len(extensions) == 1, extensions
    extension = extensions[0]
    extension_info = plistlib.loads((extension / 'Contents/Info.plist').read_bytes())
    assert extension_info['CFBundleIdentifier'] == 'io.nekohasekai.sfamt.system', extension_info
    assert list((app / 'Contents/Library/LaunchDaemons').glob('*.plist')), 'missing launch daemon'
    required = [
        app / 'Contents/MacOS' / info['CFBundleExecutable'],
        app / 'Contents/Helpers/RootHelper',
        app / 'Contents/Frameworks/Library.framework/Library',
        extension / 'Contents/MacOS' / extension_info['CFBundleExecutable'],
        extension / 'Contents/Frameworks/Library.framework/Library',
    ]
    binaries = {}
    for binary in required:
        assert binary.is_file(), f'missing {binary}'
        arches = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()
        assert set(arches) == {'arm64', 'x86_64'}, (str(binary), arches)
        binaries[str(binary.relative_to(app))] = arches
    return {
        'bundle_id': info['CFBundleIdentifier'],
        'system_extension_id': extension_info['CFBundleIdentifier'],
        'binaries': binaries,
        'signing': 'signing disabled; no Developer ID / notarization claim',
        'files': sorted(str(p.relative_to(app)) for p in app.rglob('*') if p.is_file()),
    }


if __name__ == '__main__':
    print(json.dumps(verify(sys.argv[1]), indent=2))
