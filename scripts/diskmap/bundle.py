#!/usr/bin/env python3
"""Build a relocatable local app. Set DISKMAP_SIGN_IDENTITY for Developer ID signing."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
outputBundle = root / "build/Diskmap.app"
staging = tempfile.TemporaryDirectory(prefix="diskmap-package-", dir=root / "build")
bundle = Path(staging.name) / "Diskmap.app"
contents = bundle / "Contents"
for folder in ("MacOS", "Frameworks", "Resources"):
    (contents / folder).mkdir(parents=True, exist_ok=True)
resources = contents / "Resources"
for source, target in [(root / "lua", resources / "lua"), (root / "apps/diskmap", resources / "apps/diskmap")]:
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(source, target, ignore=shutil.ignore_patterns(".git", "*.md"))
subprocess.run(["clang", "-O2", "-Wall", "-mmacosx-version-min=26.0", str(root / "scripts/diskmap/launcher.c"), "-o", str(contents / "MacOS/Diskmap")], check=True)
frameworks = contents / "Frameworks"
visited = set()
def install_library(source):
    destination = frameworks / source.name
    if source.name in visited:
        return
    visited.add(source.name)
    shutil.copy2(source.resolve(), destination)
    os.chmod(destination, 0o755)
    dependencies = subprocess.check_output(["otool", "-L", str(destination)], text=True).splitlines()[2:]
    subprocess.run(["install_name_tool", "-id", "@loader_path/" + source.name, str(destination)], check=True)
    for line in dependencies:
        dependency = line.strip().split(" (")[0]
        if dependency.startswith(("/usr/lib/", "/System/Library/")):
            continue
        if not dependency.startswith("/"):
            raise RuntimeError("Unresolved runtime dependency: " + dependency)
        path = Path(dependency)
        install_library(path)
        subprocess.run(["install_name_tool", "-change", dependency, "@loader_path/" + path.name, str(destination)], check=True)
install_library(root / "build/AppKit.dylib")
install_library(root / "build/StorageScan.dylib")
(contents / "Info.plist").write_bytes(plistlib.dumps({
    "CFBundleName": "Diskmap", "CFBundleDisplayName": "Diskmap",
    "CFBundleIdentifier": "org.luaobjc.diskmap", "CFBundleExecutable": "Diskmap",
    "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "1.0.0",
    "CFBundleVersion": "1", "LSMinimumSystemVersion": "26.0",
    "NSHighResolutionCapable": True,
    "NSDesktopFolderUsageDescription": "Measure storage used by files in your Desktop folder.",
    "NSDocumentsFolderUsageDescription": "Measure storage used by files in your Documents folder.",
    "NSDownloadsFolderUsageDescription": "Measure storage used by downloaded files.",
}))
identity = os.environ.get("DISKMAP_SIGN_IDENTITY", "-")
for target in [*(frameworks / name for name in sorted(visited)), bundle]:
    args = ["codesign", "--force", "--sign", identity]
    if identity != "-":
        args += ["--options", "runtime", "--timestamp"]
    subprocess.run(args + [str(target)], check=True)
subprocess.run(["codesign", "--verify", "--strict", "--deep", str(bundle)], check=True)
# Replace the directory, never overwrite a dylib mapped by a running app.
if outputBundle.exists():
    outputBundle.rename(Path(staging.name) / "PreviousDiskmap.app")
bundle.rename(outputBundle)
staging.cleanup()
print(outputBundle)
print("Local ad-hoc signature; distribution still needs Developer ID signing and notarization." if identity == "-" else "Signed. Notarize the app before distribution.")
