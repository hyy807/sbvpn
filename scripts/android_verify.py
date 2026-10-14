#!/usr/bin/env python3
"""Verify official APK coverage and exact patched AAR payloads; record provenance."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

ABIS = {"armeabi-v7a", "arm64-v8a", "x86", "x86_64"}
CLIENT_COMMIT = "bc73504fcb858400a939140ad785ed92f4c9f429"
PATCH_MARKER = b"github.com/sagernet/sing-box/transport/v2rayxhttp"


def git(path, *args):
    return subprocess.check_output(["git", "-C", str(path), *args], text=True).strip()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def verify(client, output):
    core = Path(__file__).resolve().parent.parent
    assert (client / ".upstream-commit").read_text().strip() == CLIENT_COMMIT, "Unexpected client revision"
    manifest = json.loads((Path(__file__).with_name("android_source_manifest.json")).read_text())
    for name, expected in manifest.items():
        assert digest((client / name).read_bytes()) == expected, f"Official source changed: {name}"
    assert not git(core, "diff", "HEAD", "--", "clients/android"), "Official client sources were modified"
    records = []
    pending = []
    for flavor, aar_name, min_sdk in [("other", "libbox.aar", 24), ("otherLegacy", "libbox-legacy.aar", 21)]:
        aar_path = core / aar_name
        with zipfile.ZipFile(aar_path) as aar:
            native = {abi: aar.read(f"jni/{abi}/libbox.so") for abi in ABIS}
        for abi, data in native.items():
            assert PATCH_MARKER in data, f"{aar_name}/{abi}: private XHTTP package missing"
        metadata_path = client / f"app/build/outputs/apk/{flavor}/debug/output-metadata.json"
        metadata = json.loads(metadata_path.read_text())
        assert metadata["applicationId"] == "io.nekohasekai.sfa"
        coverage = set()
        for entry in metadata["elements"]:
            filters = entry["filters"]
            assert all(f["filterType"] == "ABI" for f in filters), filters
            expected = {f["value"] for f in filters} if filters else ABIS
            assert expected <= ABIS and expected, expected
            key = next(iter(expected)) if len(expected) == 1 else "universal"
            assert key not in coverage, f"Duplicate APK: {flavor}/{key}"
            coverage.add(key)
            apk_path = metadata_path.parent / entry["outputFile"]
            with zipfile.ZipFile(apk_path) as apk:
                actual = {name.split('/')[1] for name in apk.namelist() if name.startswith('lib/') and name.endswith('/libbox.so')}
                assert actual == expected, (apk_path, actual, expected)
                for abi in actual:
                    assert apk.read(f"lib/{abi}/libbox.so") == native[abi], f"Wrong core in {apk_path}/{abi}"
                assert "AndroidManifest.xml" in apk.namelist()
                assert "classes.dex" in apk.namelist()
            name = f"sbvpn-{flavor}-{key}-debug.apk"
            records.append({"file": name, "sha256": digest(apk_path.read_bytes()), "abis": sorted(actual),
                            "min_sdk": min_sdk, "version_code": entry["versionCode"], "version_name": entry["versionName"],
                            "native_sha256": {abi: digest(native[abi]) for abi in sorted(actual)}})
            pending.append((apk_path, name))
        assert coverage == ABIS | {"universal"}, f"Missing APKs: {flavor}: {coverage}"
    output.mkdir(parents=True, exist_ok=True)
    for source, name in pending:
        shutil.copyfile(source, output / name)
    provenance = {"core_commit": git(core, "rev-parse", "HEAD"), "client_repository": "https://github.com/SagerNet/sing-box-for-android",
                  "client_commit": CLIENT_COMMIT, "signing": "debug (not official release key)",
                  "build_command": "go run ./cmd/internal/build_libbox -target android; ./gradlew :app:assembleOtherDebug :app:assembleOtherLegacyDebug --no-daemon",
                  "run_url": f"https://github.com/{os.getenv('GITHUB_REPOSITORY', '')}/actions/runs/{os.getenv('GITHUB_RUN_ID', '')}",
                  "aars": {name: digest((core / name).read_bytes()) for name in ["libbox.aar", "libbox-legacy.aar"]}, "apks": records}
    (output / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    (output / "SHA256SUMS").write_text("".join(f"{r['sha256']}  {r['file']}\n" for r in sorted(records, key=lambda r: r['file'])))
    print(f"Verified {len(records)} APKs: both official flavors, 4 ABI splits + universal each; exact patched libbox payloads.")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: android_verify.py CLIENT_DIRECTORY OUTPUT_DIRECTORY")
    verify(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
