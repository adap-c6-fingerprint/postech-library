#!/bin/bash
set -euo pipefail
# 먼저 postman simulation run postman/simulations/appstore-api-routing.sim.yaml --port 47585 --no-history 를 실행한다.
cd "$(dirname "$0")/.."
proof_binary="${TMPDIR:-/tmp}/postech-appstore-api-routing-proof"
xcrun swiftc -swift-version 6 -DDEBUG -parse-as-library \
  fingerprint-library/Clients/Network/HTTPClient.swift \
  fingerprint-library/Clients/Network/BookAPIClient.swift \
  fingerprint-library/Shared/AppConfiguration.swift \
  fingerprint-library/Clients/Book/Client/PrimoAPIClient.swift \
  fingerprint-library/Clients/Book/Client/Data4LibraryAPIClient.swift \
  Scripts/verify-appstore-api-routing.swift -o "$proof_binary"
exec "$proof_binary" "$@"
