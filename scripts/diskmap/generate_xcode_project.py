#!/usr/bin/env python3
"""Generate the minimal macOS App Store Xcode project for Diskmap."""

from pathlib import Path
import shutil


ROOT = Path(__file__).resolve().parents[2]
TEMPLATE = ROOT / "scripts/diskmap/xcode-project-template"
PROJECT = ROOT / "apps/diskmap/Diskmap.xcodeproj"


def main() -> None:
	for source in TEMPLATE.rglob("*"):
		if not source.is_file():
			continue
		relative = source.relative_to(TEMPLATE)
		destination = PROJECT / relative
		destination.parent.mkdir(parents=True, exist_ok=True)
		shutil.copy2(source, destination)

	print(f"Generated {PROJECT.relative_to(ROOT)}")


if __name__ == "__main__":
	main()
