#!/usr/bin/env python3
"""Add Lua sources and assets to Xcode's Adventure Arena product before signing."""
import argparse
from pathlib import Path
import shutil

from bundle import copy_tree


def populate(bundle: Path) -> None:
    workspace = bundle / 'Workspace'
    if workspace.exists():
        shutil.rmtree(workspace)
    copy_tree('lua', workspace, lua_only=True)
    copy_tree('apps/adventure-arena', workspace)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', required=True, type=Path)
    args = parser.parse_args()
    populate(args.bundle)


if __name__ == '__main__':
    main()
