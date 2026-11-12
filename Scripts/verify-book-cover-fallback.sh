#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
proof_binary="${TMPDIR:-/tmp}/postech-book-cover-proof"
xcrun swiftc -swift-version 6 -parse-as-library \
  fingerprint-library/Clients/Network/HTTPClient.swift \
  fingerprint-library/Clients/Network/BookAPIClient.swift \
  fingerprint-library/Clients/Network/AppConfiguration.swift \
  fingerprint-library/Clients/Book/Client/Yes24BookDetailService.swift \
  fingerprint-library/Clients/Book/Cache/Yes24BookCoverResolver.swift \
  fingerprint-library/Clients/Book/Cache/RecommendationCachePreparer.swift \
  fingerprint-library/Clients/Book/Cache/RecommendationCacheStore.swift \
  fingerprint-library/Domain/Book/Book.swift \
  fingerprint-library/Domain/Book/BookISBN.swift \
  fingerprint-library/Domain/Book/BookDescription.swift \
  fingerprint-library/Domain/Book/BookText.swift \
  fingerprint-library/UI/BookCover/BookCoverFailure.swift \
  fingerprint-library/UI/BookCover/BookCoverSource.swift \
  fingerprint-library/UI/BookCover/SharedImageLoader.swift \
  fingerprint-library/UI/BookCover/BookCoverModel.swift \
  Scripts/verify-book-cover-fallback.swift -o "$proof_binary"
exec "$proof_binary" "$@"
