#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
proof_binary="${TMPDIR:-/tmp}/postech-call-number-sticker-proof"
xcrun swiftc -swift-version 6 -parse-as-library \
  fingerprint-library/Features/BookNavigation/Presentation/BookNavigationArrivalCallNumber.swift \
  fingerprint-library/Features/BookNavigation/Presentation/BookNavigationCallNumberLabelLayout.swift \
  Scripts/verify-call-number-sticker.swift -o "$proof_binary"
exec "$proof_binary"
