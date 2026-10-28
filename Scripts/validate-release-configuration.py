#!/usr/bin/env python3
"""Reject Release builds that cannot perform Primo holdings lookups."""

import os
import sys
from urllib.parse import urlsplit


def validate(configuration: str, proxy_url: str) -> None:
    if configuration != "Release":
        return
    value = proxy_url.strip()
    if not value or value.startswith("$("):
        raise ValueError(
            "Release requires PRIMO_PROXY_URL. Set it in the ignored Secrets.xcconfig "
            "or supply the PRIMO_PROXY_URL build setting in your private archive pipeline."
        )
    try:
        parts = urlsplit(value)
        valid = (
            value == proxy_url
            and value.startswith("https://")
            and parts.scheme == "https"
            and parts.hostname is not None
            and parts.port != 0
            and parts.username is None
            and parts.password is None
            and "?" not in value
            and "#" not in value
            and not any(character.isspace() for character in value)
        )
    except ValueError:
        valid = False
    if not valid:
        raise ValueError(
            "PRIMO_PROXY_URL must be an HTTPS base URL without credentials, "
            "query parameters or fragments."
        )


if __name__ == "__main__":
    try:
        validate(os.environ.get("CONFIGURATION", ""), os.environ.get("PRIMO_PROXY_URL", ""))
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
