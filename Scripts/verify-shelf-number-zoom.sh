#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
proof_binary="${TMPDIR:-/tmp}/postech-shelf-number-zoom-proof"
xcrun swiftc -swift-version 6 -parse-as-library \
  fingerprint-library/Domain/IndoorMap/IndoorMap.swift \
  fingerprint-library/Domain/IndoorMap/IndoorMapGeometry+Queries.swift \
  fingerprint-library/Domain/IndoorMap/IndoorShelfLabel.swift \
  fingerprint-library/Features/IndoorMap/Components/Common/Map/MapKitGeometry.swift \
  fingerprint-library/Features/IndoorMap/Presentation/IndoorShelfLabelLayout.swift \
  Scripts/verify-shelf-number-zoom.swift -o "$proof_binary"
exec "$proof_binary"
