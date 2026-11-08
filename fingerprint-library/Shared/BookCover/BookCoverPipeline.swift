import UIKit
import OSLog
import ComposableArchitecture

@MainActor
enum BookCoverPipeline {
    private static let logger = Logger(subsystem: "Fingerprint", category: "BookCover")
    
    static let yes24Cover = Yes24BookCoverResolver { isbn13 in
        @Dependency(\.httpClient) var httpClient
        return try await Yes24BookDetailService(relay: .init(httpClient: httpClient))
            .fetchCoverURL(isbn13: isbn13)
    }

    /// 이전에 파일 경로만 저장한 책은 도서관 응답에서 같은 서지의 표지를 다시 찾는다.
    static func originalCoverURL(for book: Book) async throws -> URL? {
        guard let recordID = BookHoldingsClient.recordID(for: book) else { return nil }
        @Dependency(\.httpClient) var httpClient
        let response = try await PrimoAPIClient(relay: .init(httpClient: httpClient)).search(recordID: recordID)
        guard response.isSuccessful else { throw PrimoAPIError.invalidResponse }
        return try PrimoBookMapper.books(from: response.data)
            .first { $0.id == "primo:\(recordID)" }?.imageURL
    }
    
    //책등 (폴백과는 관련 없음)
    static let bookSpineCover = Yes24BookCoverResolver { isbn13 in
        @Dependency(\.httpClient) var httpClient
        return try await Yes24BookDetailService(relay: .init(httpClient: httpClient))
            .fetchSpineURL(isbn13: isbn13)
    }
    
    private static var spineURLs: [String: URL] = [:]
    // ISBN13 → 책등 이미지 주소. 표지(BookCoverModel)처럼 화면이 뜰 때 메모리 캐시를 바로 찾으려고 MainActor에 둔다.

    /// 책등 이미지를 표지와 같은 메모리 캐시(shared)로 받는다.
    static func spineImage(isbn: String) async throws -> UIImage {
        guard let isbn13 = BookISBN.isbn13(from: isbn),
              let url = try await bookSpineCover.url(for: isbn13) else {
            throw RecommendationCacheStore.CacheError.invalidImage
        }
        spineURLs[isbn13] = url
        return try await shared.image(for: url)
    }

    /// 이미 받아 둔 책등 이미지를 기다리지 않고 바로 꺼낸다. 없으면 nil
    static func cachedSpineImage(isbn: String) -> UIImage? {
        guard let isbn13 = BookISBN.isbn13(from: isbn), let url = spineURLs[isbn13] else { return nil }
        return shared.cachedImage(for: url)
        // 메모리 캐시에서 밀려났으면 nil이 되어 다시 받는다.
    }

    /// 길안내를 시작할 때 책등 이미지를 미리 받아 표지와 같은 메모리 캐시(shared)에 넣어 둔다.
    static func prefetchSpines(isbns: [String]) {
        let targets = Set(isbns.compactMap { BookISBN.isbn13(from: $0) })
        for isbn13 in targets where cachedSpineImage(isbn: isbn13) == nil {
            Task { _ = try? await spineImage(isbn: isbn13) }
        }
        // 화면 작업(Effect)과 떼어 두어, 상세·장바구니 화면이 닫혀도 끝까지 받는다.
        // 같은 ISBN을 이미 받는 중이면 Yes24BookCoverResolver와 shared가 진행 중 요청을 함께 쓴다.
    }

    /// 추천·검색·상세가 같은 메모리 캐시와 진행 중 요청을 사용한다.
    static let shared = SharedImageLoader<UIImage>(
        readLocalImage: { url in
            guard url.isFileURL else { return nil }
            return UIImage(contentsOfFile: url.path)
        },
        cost: { image in
            guard let cgImage = image.cgImage else { return 1 }
            return cgImage.bytesPerRow * cgImage.height
        },
        loadImage: { url in
            do {
                if url.isFileURL {
                    guard let image = UIImage(contentsOfFile: url.path) else {
                        throw BookCoverFailure.unreadableLocalFile
                    }
                    return image
                }
                return try await BookCoverRemoteLoader.image(for: url, download: download)
            } catch {
                guard !Task.isCancelled else { throw CancellationError() }
                let diagnostic = BookCoverFailure.diagnostic(for: error)
                // URL·ISBN·헤더·응답 본문·error.localizedDescription은 기록하지 않는다.
                logger.notice("Cover load: reason=\(diagnostic.reason, privacy: .public) http=\(diagnostic.httpStatus) transport=\(diagnostic.transportCode)")
                throw error
            }
        }
    )

    private static func download(_ url: URL) async throws -> UIImage {
        @Dependency(\.httpClient) var httpClient
        let result: HTTPResponse
        do {
            result = try await httpClient.send(URLRequest(url: url))
        } catch is HTTPClientError {
            throw BookCoverFailure.invalidResponse
        }
        try BookCoverFailure.validate(data: result.data, response: result.response)
        guard let image = UIImage(data: result.data) else { throw BookCoverFailure.invalidImage }
        return image
    }
}
