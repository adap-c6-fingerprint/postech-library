#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
proof_binary="${TMPDIR:-/tmp}/postech-book-cover-proof"
xcrun swiftc -swift-version 6 -parse-as-library \
  fingerprint-library/Clients/Network/HTTPClient.swift \
  fingerprint-library/Clients/Network/BookAPIClient.swift \
  fingerprint-library/Shared/AppConfiguration.swift \
  fingerprint-library/Clients/Book/Client/Yes24BookDetailService.swift \
  fingerprint-library/Clients/Book/Cache/Yes24BookCoverResolver.swift \
  fingerprint-library/Domain/Book/BookISBN.swift \
  fingerprint-library/Domain/Book/BookDescription.swift \
  fingerprint-library/Shared/BookText.swift \
  fingerprint-library/Shared/BookCover/BookCoverFailure.swift \
  fingerprint-library/Shared/BookCover/SharedImageLoader.swift \
  fingerprint-library/Shared/BookCover/BookCoverModel.swift \
  Scripts/verify-book-cover-fallback.swift -o "$proof_binary"
exec "$proof_binary" "$@"
