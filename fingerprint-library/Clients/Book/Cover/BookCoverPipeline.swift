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

    static func originalCoverURL(for book: Book) async throws -> URL? {
        guard let recordID = BookHoldingsClient.recordID(for: book) else { return nil }
        @Dependency(\.httpClient) var httpClient
        let response = try await PrimoAPIClient(relay: .init(httpClient: httpClient)).search(recordID: recordID)
        guard response.isSuccessful else { throw PrimoAPIError.invalidResponse }
        return try PrimoBookMapper.books(from: response.data)
            .first { $0.id == "primo:\(recordID)" }?.imageURL
    }

    static let bookSpineCover = Yes24BookCoverResolver { isbn13 in
        @Dependency(\.httpClient) var httpClient
        return try await Yes24BookDetailService(relay: .init(httpClient: httpClient))
            .fetchSpineURL(isbn13: isbn13)
    }
    
    private static var spineURLs: [String: URL] = [:]

    static func spineImage(isbn: String) async throws -> UIImage {
        guard let isbn13 = BookISBN.isbn13(from: isbn),
              let url = try await bookSpineCover.url(for: isbn13) else {
            throw RecommendationCacheStore.CacheError.invalidImage
        }
        spineURLs[isbn13] = url
        return try await shared.image(for: url)
    }

    static func cachedSpineImage(isbn: String) -> UIImage? {
        guard let isbn13 = BookISBN.isbn13(from: isbn), let url = spineURLs[isbn13] else { return nil }
        return shared.cachedImage(for: url)
    }

    static func prefetchSpines(isbns: [String]) {
        let targets = Set(isbns.compactMap { BookISBN.isbn13(from: $0) })
        for isbn13 in targets where cachedSpineImage(isbn: isbn13) == nil {
            Task { _ = try? await spineImage(isbn: isbn13) }
        }
    }

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
