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
    var spineImage: @Sendable (String) async throws -> UIImage
    // 책등 이미지를 표지와 같은 메모리 캐시로 받는다. PNG로 바꾸지 않는다.
    // 책등은 URL기반이 아니라 ISBN 13자리 기반이라서 String임
    var cachedSpineImage: @MainActor @Sendable (String) -> UIImage?
    // 이미 받아 둔 책등 이미지를 기다리지 않고 바로 꺼낸다. 화면이 뜰 때 플레이스홀더를 거치지 않게 한다.
    var prefetchSpines: @MainActor @Sendable ([String]) -> Void
    // 길안내를 시작할 때 책등 이미지를 미리 받아 둔다. 기다리지 않고 바로 돌아온다.
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


extension DependencyValues {
    var bookCoverClient: BookCoverClient {
        get { self[BookCoverClient.self] }
        set { self[BookCoverClient.self] = newValue }
    }
}
