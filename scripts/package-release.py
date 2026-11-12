"""Package the built app and emit a source-bound macOS release manifest."""
import hashlib
import json
import plistlib
import re
import shutil
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
info = plistlib.loads((root / "Info.plist").read_bytes())
version = info["CFBundleShortVersionString"]
if not re.fullmatch(r"\d{1,6}\.\d{1,6}\.\d{1,6}", version):
    raise SystemExit("Invalid version")
revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
dist = root / "dist"
dist.mkdir(exist_ok=True)
stage = root / "build/dmg"
if stage.exists():
    raise SystemExit("DMG staging folder exists. Build in a fresh checkout.")
stage.mkdir(parents=True)
shutil.copytree(root / "Ego Tab Search.app", stage / "Ego Tab Search.app")
(stage / "Applications").symlink_to("/Applications", target_is_directory=True)
image = dist / f"Ego-Tab-Search-{version}-arm64.dmg"
subprocess.run(["hdiutil", "create", "-volname", "Ego Tab Search", "-srcfolder", str(stage),
                "-format", "UDZO", str(image)], check=True)
subprocess.run(["hdiutil", "verify", str(image)], check=True)
digest = hashlib.sha256(image.read_bytes()).hexdigest()
manifest = {
    "schema_version": 1, "component": "ego-tab-search-macos",
    "source": {"repository": "111pointer111/ego-lite-tab-search", "revision": revision},
    "version": version, "build": int(info["CFBundleVersion"]), "channel": "preview", "platform": "macos",
    "architectures": ["arm64"], "minimum_os": info["LSMinimumSystemVersion"],
    "signing": {"developer_id": False, "notarized": False},
    "artifact": {"name": image.name, "sha256": digest, "size": image.stat().st_size},
}
(dist / "desktop-release.json").write_text(json.dumps(manifest, indent=2) + "\n")
(dist / "SHA256SUMS.txt").write_text(f"{digest}  {image.name}\n")
print(json.dumps(manifest, indent=2))
