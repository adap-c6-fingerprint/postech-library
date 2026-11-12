#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
proof_binary="${TMPDIR:-/tmp}/postech-navigation-progress-labels-proof"
xcrun swiftc -swift-version 6 -parse-as-library \
  fingerprint-library/Domain/IndoorMap/IndoorMap.swift \
  fingerprint-library/Domain/IndoorMap/IndoorMapGeometry+Queries.swift \
  fingerprint-library/Domain/IndoorMap/IndoorPosition.swift \
  fingerprint-library/Domain/IndoorMap/ShelfDirectory.swift \
  fingerprint-library/Domain/Routing/RoutingGraph.swift \
  fingerprint-library/Domain/Routing/RoutingGeometry.swift \
  fingerprint-library/Domain/Routing/IndoorRoute.swift \
  fingerprint-library/Domain/Routing/RouteGuidancePlan.swift \
  fingerprint-library/Features/BookNavigation/Presentation/BookNavigationTimeline.swift \
  fingerprint-library/Features/BookNavigation/Presentation/BookNavigationProgressLayout.swift \
  Scripts/verify-navigation-progress-labels.swift -o "$proof_binary"
exec "$proof_binary"
