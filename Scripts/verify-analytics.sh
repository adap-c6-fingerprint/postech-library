#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
proof_dir="$(mktemp -d /private/tmp/pobook-analytics.XXXXXX)"
trap 'rm -rf "$proof_dir"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor \
  -module-cache-path "$proof_dir/modules" -parse-as-library \
  fingerprint-library/Domain/Book/Book.swift \
  fingerprint-library/Domain/Analytics/AnalyticsEvent.swift \
  Scripts/verify-analytics.swift -o "$proof_dir/verify-analytics"
"$proof_dir/verify-analytics"
