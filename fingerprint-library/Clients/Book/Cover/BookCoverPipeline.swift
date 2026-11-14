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
    private static let spineFiles = BookSpineFileStore.live

    static func spineImage(isbn: String) async throws -> UIImage {
        if let image = cachedSpineImage(isbn: isbn) { return image }
        guard let isbn13 = BookISBN.isbn13(from: isbn) else {
            throw RecommendationCacheStore.CacheError.invalidImage
        }
        switch await loadSavedSpine(isbn13: isbn13) {
        case let .image(image): return image
        case .missing: throw RecommendationCacheStore.CacheError.invalidImage
        case .notSaved: break
        }
        guard let url = try await bookSpineCover.url(for: isbn13) else {
            await markSpineMissing(isbn13: isbn13)
            throw RecommendationCacheStore.CacheError.invalidImage
        }
        spineURLs[isbn13] = url
        let image = try await shared.image(for: url)
        await saveSpine(image, isbn13: isbn13)
        return image
    }
    // 메모리 → 기기에 저장된 파일 → Yes24 API 순서로 찾는다. 이미지나 '없음' 표시가 저장돼 있으면 API를 부르지 않는다.

    static func cachedSpineImage(isbn: String) -> UIImage? {
        guard let isbn13 = BookISBN.isbn13(from: isbn), let url = spineURLs[isbn13] else { return nil }
        return shared.memoryImage(for: url)
    }
    // 메모리만 확인한다. 화면 진입 시 메인 스레드에서 파일을 읽지 않기 위해서다.

    static func preloadSavedSpines(isbns: [String]) async {
        let targets = Set(isbns.compactMap { BookISBN.isbn13(from: $0) })
        for isbn13 in targets where cachedSpineImage(isbn: isbn13) == nil && !missingSpines.contains(isbn13) {
            _ = await loadSavedSpine(isbn13: isbn13)
        }
    }
    // 앱 시작 시 최근 찾은 책의 책등 파일을 백그라운드에서 읽어 메모리에 올려 둔다.

    private enum SavedSpine {
        case image(UIImage)
        case missing
        case notSaved
    }

    private static var missingSpines: Set<String> = []

    private static func loadSavedSpine(isbn13: String) async -> SavedSpine {
        if missingSpines.contains(isbn13) { return .missing }
        let store = spineFiles
        let (image, isMissing) = await Task.detached(priority: .utility) {
            let image = UIImage(contentsOfFile: store.fileURL(isbn13: isbn13).path)?.preparingForDisplay()
            return (image, image == nil && store.isMarkedMissing(isbn13: isbn13))
        }.value
        if let image {
            let file = store.fileURL(isbn13: isbn13)
            shared.insert(image, for: file)
            spineURLs[isbn13] = file
            return .image(image)
        }
        if isMissing {
            missingSpines.insert(isbn13)
            return .missing
        }
        return .notSaved
    }
    // 파일 읽기와 이미지 디코딩은 백그라운드에서 하고, 메모리 캐시 반영만 메인에서 한다.

    private static func markSpineMissing(isbn13: String) async {
        missingSpines.insert(isbn13)
        let store = spineFiles
        let failure = await Task.detached(priority: .utility) { () -> Error? in
            do {
                try store.markMissing(isbn13: isbn13)
                return nil
            } catch {
                return error
            }
        }.value
        if let failure {
            logger.notice("Spine missing mark failed: \(failure.localizedDescription, privacy: .public)")
        }
    }

    private static func saveSpine(_ image: UIImage, isbn13: String) async {
        let store = spineFiles
        let failure = await Task.detached(priority: .utility) { () -> Error? in
            guard let data = image.pngData() else { return nil }
            do {
                try store.save(data, isbn13: isbn13)
                return nil
            } catch {
                return error
            }
        }.value
        if let failure {
            logger.notice("Spine save failed: \(failure.localizedDescription, privacy: .public)")
        }
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
