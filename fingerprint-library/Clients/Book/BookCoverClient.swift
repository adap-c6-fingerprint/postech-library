//
//  BookCoverClient.swift
//  fingerprint-library
//
//  Created by 이시온 on 10/30/26.
//

import ComposableArchitecture
import Foundation
import UIKit

nonisolated struct BookCoverClient: Sendable {
    var prefetch: @Sendable ([URL]) async -> Void
    var pngData: @Sendable (URL) async throws -> Data
    var spineImage: @Sendable (String) async throws -> UIImage
    var cachedSpineImage: @MainActor @Sendable (String) -> UIImage?
    var prefetchSpines: @MainActor @Sendable ([String]) -> Void
}

extension BookCoverClient: DependencyKey {
    static let liveValue = Self(
        prefetch: { urls in
            await BookCoverPipeline.shared.prefetch(urls)
        },
        pngData: { url in
            let image = try await BookCoverPipeline.shared.image(for: url)
            guard let data = await MainActor.run(body: { image.pngData() }) else {
                throw RecommendationCacheStore.CacheError.invalidImage
            }
            return data
        },
        spineImage: { isbn in
            try await BookCoverPipeline.spineImage(isbn: isbn)
        },
        cachedSpineImage: { isbn in
            BookCoverPipeline.cachedSpineImage(isbn: isbn)
        },
        prefetchSpines: { isbns in
            BookCoverPipeline.prefetchSpines(isbns: isbns)
        }
    )
    static let testValue = Self(
        prefetch: { _ in },
        pngData: { _ in throw RecommendationCacheStore.CacheError.invalidImage },
        spineImage: { _ in throw RecommendationCacheStore.CacheError.invalidImage },
        cachedSpineImage: { _ in nil },
        prefetchSpines: { _ in }
    )
}


nonisolated extension DependencyValues {
    var bookCoverClient: BookCoverClient {
        get { self[BookCoverClient.self] }
        set { self[BookCoverClient.self] = newValue }
    }
}
