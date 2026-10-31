#!/usr/bin/env python3
"""Validate relay credentials for Release archives. Never print tokens."""

import os
import sys


def validate(configuration: str, channel: str, development: str = "", testflight: str = "", production: str = "") -> None:
    if channel not in ("automatic", "internal"):
        raise ValueError("POBOOK_BUILD_CHANNEL must be automatic or internal.")
    if configuration != "Release":
        return
    required = {"DEVELOPMENT": development} if channel == "internal" else {"TESTFLIGHT": testflight, "PRODUCTION": production}
    for name, value in required.items():
        if len(value) < 32 or value.startswith("$(") or any(not 0x21 <= ord(character) <= 0x7e for character in value):
            raise ValueError(f"Release requires a valid POBOOK_RELAY_TOKEN_{name} in private build settings.")


if __name__ == "__main__":
    try:
        validate(os.environ.get("CONFIGURATION", ""), os.environ.get("POBOOK_BUILD_CHANNEL", "automatic"),
                 os.environ.get("POBOOK_RELAY_TOKEN_DEVELOPMENT", ""), os.environ.get("POBOOK_RELAY_TOKEN_TESTFLIGHT", ""),
                 os.environ.get("POBOOK_RELAY_TOKEN_PRODUCTION", ""))
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
