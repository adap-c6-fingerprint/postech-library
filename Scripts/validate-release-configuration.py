#!/usr/bin/env python3
"""Validate relay credentials for Release archives. Never print tokens."""

import os
import sys


def validate(configuration: str, channel: str, development: str = "", testflight: str = "", production: str = "",
             action: str = "build") -> None:
    if channel not in ("automatic", "internal"):
        raise ValueError("POBOOK_BUILD_CHANNEL must be automatic or internal.")
    # Archive/install builds must not package the internal relay channel.
    if action in ("install", "archive") and (configuration != "Release" or channel != "automatic"):
        raise ValueError("Archive/install requires Release and POBOOK_BUILD_CHANNEL=automatic; internal is for local builds only.")
    if configuration != "Release":
        return
    required = {"DEVELOPMENT": development} if channel == "internal" else {
        "DEVELOPMENT": development, "TESTFLIGHT": testflight, "PRODUCTION": production
    }
    for name, value in required.items():
        if len(value) < 32 or value.startswith("$(") or any(not 0x21 <= ord(character) <= 0x7e for character in value):
            raise ValueError(f"Release requires a valid POBOOK_RELAY_TOKEN_{name} in private build settings.")
    if len(set(required.values())) != len(required):
        raise ValueError("Release relay tokens must be distinct across environments.")


if __name__ == "__main__":
    try:
        validate(os.environ.get("CONFIGURATION", ""), os.environ.get("POBOOK_BUILD_CHANNEL", "automatic"),
                 os.environ.get("POBOOK_RELAY_TOKEN_DEVELOPMENT", ""), os.environ.get("POBOOK_RELAY_TOKEN_TESTFLIGHT", ""),
                 os.environ.get("POBOOK_RELAY_TOKEN_PRODUCTION", ""), action=os.environ.get("ACTION", "build"))
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
