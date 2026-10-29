import Foundation
import Observation

/// UIKit과 분리해 표지 없음·실패·취소·재시도의 전이를 오프라인에서도 검증한다.
@MainActor
@Observable
final class BookCoverModel<Image: Sendable> {
    enum Phase {
        case loading
        case loaded(Image)
        case failed
        case unavailable
    }

    private var url: URL?
    private var isbn13: String?
    private var currentPhase: Phase
    private var requestID: UUID?
    private let pipeline: SharedImageLoader<Image>
    private let fallback: @Sendable (String) async throws -> URL?

    init(url: URL?, isbn: String? = nil, pipeline: SharedImageLoader<Image>,
         fallback: @escaping @Sendable (String) async throws -> URL? = { _ in nil }) {
        let isbn13 = BookISBN.isbn13(from: isbn)
        self.url = url
        self.isbn13 = isbn13
        self.pipeline = pipeline
        self.fallback = fallback
        currentPhase = url.map { url in
            pipeline.cachedImage(for: url).map(Phase.loaded) ?? .loading
        } ?? (isbn13 == nil ? .unavailable : .loading)
    }

    func phase(for url: URL?, isbn: String? = nil) -> Phase {
        let isbn13 = BookISBN.isbn13(from: isbn)
        guard self.url == url, self.isbn13 == isbn13 else {
            return url.flatMap(pipeline.cachedImage).map(Phase.loaded)
                ?? (url == nil && isbn13 == nil ? .unavailable : .loading)
        }
        return currentPhase
    }

    func load(_ url: URL?, isbn: String? = nil) async {
        let id = UUID()
        requestID = id
        self.url = url
        let isbn13 = BookISBN.isbn13(from: isbn)
        self.isbn13 = isbn13
        guard url != nil || isbn13 != nil else {
            currentPhase = .unavailable
            return
        }
        if let image = url.flatMap(pipeline.cachedImage) {
            currentPhase = .loaded(image)
            return
        }
        currentPhase = .loading
        do {
            let image = try await image(primaryURL: url, isbn13: isbn13)
            try Task.checkCancellation()
            guard requestID == id else { return }
            currentPhase = .loaded(image)
        } catch {
            guard !Task.isCancelled, requestID == id else { return }
            currentPhase = BookCoverFailure.isUnavailable(error) ? .unavailable : .failed
        }
    }

    private func image(primaryURL: URL?, isbn13: String?) async throws -> Image {
        if let primaryURL {
            do { return try await pipeline.image(for: primaryURL) }
            catch {
                try Task.checkCancellation()
                guard isbn13 != nil else { throw error }
            }
        }
        try Task.checkCancellation()
        guard let isbn13, let fallbackURL = try await fallback(isbn13) else {
            throw BookCoverFailure.unavailable(statusCode: 0)
        }
        try Task.checkCancellation()
        return try await pipeline.image(for: fallbackURL)
    }
}
