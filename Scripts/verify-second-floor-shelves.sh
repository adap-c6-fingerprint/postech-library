#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
proof_directory="$(mktemp -d "${TMPDIR:-/tmp}/postech-second-floor-proof.XXXXXX")"
xcrun swiftc -swift-version 6 -parse-as-library \
  fingerprint-library/Domain/Book/*.swift \
  fingerprint-library/Domain/IndoorMap/*.swift \
  fingerprint-library/Domain/Routing/*.swift \
  fingerprint-library/Domain/Routing/Search/*.swift \
  fingerprint-library/Clients/IndoorMap/BundledIndoorMapLoader.swift \
  fingerprint-library/Clients/IndoorMap/BundledShelfLabelLoader.swift \
  fingerprint-library/Clients/IndoorMap/IMDFDTO.swift \
  fingerprint-library/Clients/IndoorMap/IMDFMapper.swift \
  fingerprint-library/Clients/IndoorMap/IndoorMapLoadError.swift \
  fingerprint-library/Clients/IndoorRouting/RoutePlanningLoader.swift \
  fingerprint-library/Clients/IndoorRouting/RoutingGraphDTO.swift \
  fingerprint-library/Clients/IndoorRouting/RoutingGraphMapper.swift \
  Scripts/verify-second-floor-shelves.swift -o "$proof_directory/verify"
exec "$proof_directory/verify" "$PWD"
