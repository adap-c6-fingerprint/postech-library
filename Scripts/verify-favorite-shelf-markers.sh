#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
proof_binary="${TMPDIR:-/tmp}/postech-favorite-shelf-markers-proof"
xcrun swiftc -swift-version 6 -parse-as-library \
  fingerprint-library/Domain/IndoorMap/IndoorMap.swift \
  fingerprint-library/Domain/IndoorMap/IndoorMapGeometry+Queries.swift \
  fingerprint-library/Domain/IndoorMap/IndoorShelfLabel.swift \
  fingerprint-library/Domain/Routing/RoutingGeometry.swift \
  fingerprint-library/Domain/IndoorMap/BookShelfRangeMatcher.swift \
  fingerprint-library/Domain/IndoorMap/ShelfResolver.swift \
  fingerprint-library/Domain/Book/BookHolding.swift \
  fingerprint-library/UI/Map/HomeMapMarker.swift \
  Scripts/verify-favorite-shelf-markers.swift -o "$proof_binary"
exec "$proof_binary"
