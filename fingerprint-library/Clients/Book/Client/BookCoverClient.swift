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
    // 표지 주소들을 미리 내려받아 메모리에 넣어 둔다.
    var pngData: @Sendable (URL) async throws -> Data
    // 표지 하나를 내려받아(이미 받았으면 메모리에서) PNG 데이터로 돌려준다.
    var spinePngData: @Sendable (String) async throws -> Data
    // 책등 표지를 내려받아 PNG 데이터로 돌려준다
    // 책등은 URL기반이 아니라 ISBN 13자리 기반이라서 String임
}

extension BookCoverClient: DependencyKey {
    static let liveValue = Self(
        prefetch: { urls in
            await BookCoverPipeline.shared.prefetch(urls)
            // .shared 호출
        },
        pngData: { url in
            // 화면에서 이미 받았거나 받고 있는 표지는 기존 공통 로더의 결과를 공유한다.
            let image = try await BookCoverPipeline.shared.image(for: url)
            // .shared 호출
            guard let data = await MainActor.run(body: { image.pngData() }) else {
                throw RecommendationCacheStore.CacheError.invalidImage
            }
            return data
        },
        spinePngData: { isbn in
            guard let url = try await BookCoverPipeline.bookSpineCover.url(for: isbn) else {
                throw RecommendationCacheStore.CacheError.invalidImage
            }
            let image = try await BookCoverPipeline.shared.image(for: url)
            guard let data = await MainActor.run(body: { image.pngData() }) else {
                throw RecommendationCacheStore.CacheError.invalidImage
            }
            return data
        }
    )
    static let testValue = Self(
        prefetch: { _ in },
        pngData: { _ in throw RecommendationCacheStore.CacheError.invalidImage },
        spinePngData: { _ in throw RecommendationCacheStore.CacheError.invalidImage }
    )
}


extension DependencyValues {
    var bookCoverClient: BookCoverClient {
        get { self[BookCoverClient.self] }
        set { self[BookCoverClient.self] = newValue }
    }
}
