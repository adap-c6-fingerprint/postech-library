#!/usr/bin/env python3
"""Locate this workspace's Firebase checkout independently of its build location."""

import os
from pathlib import Path
import plistlib
import sys


TOOL = Path("SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols")


def resolve_upload_symbols(build_dir: str, cache_dir: str, workspace_path: str,
                           project_path: str = "") -> Path:
    # Firebase's standard location works when build products remain in DerivedData.
    standard = Path(build_dir.split("/Build/", 1)[0]) / TOOL
    if standard.is_file():
        return standard

    # Custom build locations move build products, but leave package checkouts behind.
    # Match Xcode's workspace metadata so another project's Firebase is never selected.
    workspaces = {Path(path).resolve() for path in (workspace_path, project_path) if path}
    cache = Path(cache_dir)
    roots = [cache, *(cache.iterdir() if cache.is_dir() else [])]
    matches = set()
    for root in roots:
        info = root / "info.plist"
        tool = root / TOOL
        if not info.is_file() or not tool.is_file():
            continue
        try:
            metadata = plistlib.loads(info.read_bytes())
        except (OSError, plistlib.InvalidFileException):
            continue
        recorded = metadata.get("WorkspacePath")
        if recorded and Path(recorded).resolve() in workspaces:
            matches.add(tool.resolve())
    if len(matches) == 1:
        return matches.pop()
    raise ValueError(
        "Could not uniquely locate this workspace's Firebase upload-symbols. "
        "Resolve package dependencies in Xcode, then archive again."
    )


if __name__ == "__main__":
    try:
        tool = resolve_upload_symbols(
            os.environ["BUILD_DIR"], os.environ["SDK_STAT_CACHE_DIR"],
            os.environ.get("WORKSPACE_PATH") or os.environ["PROJECT_FILE_PATH"],
            project_path=os.environ["PROJECT_FILE_PATH"],
        )
        os.execv(str(tool), [str(tool), "--build-phase"])
    except (KeyError, OSError, ValueError) as error:
        print(f"error: Crashlytics symbol upload: {error}", file=sys.stderr)
        sys.exit(1)
