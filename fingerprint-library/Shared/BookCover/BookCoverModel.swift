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
    private let lookupYes24: @Sendable (String) async throws -> URL?

    init(url: URL?, isbn: String? = nil, pipeline: SharedImageLoader<Image>,
         lookupYes24: @escaping @Sendable (String) async throws -> URL? = { _ in nil }) {
        let isbn13 = BookISBN.isbn13(from: isbn)
        self.url = url
        self.isbn13 = isbn13
        self.pipeline = pipeline
        self.lookupYes24 = lookupYes24
        currentPhase = Self.initialPhase(url: url, isbn13: isbn13, pipeline: pipeline)
    }

    func phase(for url: URL?, isbn: String? = nil) -> Phase {
        let isbn13 = BookISBN.isbn13(from: isbn)
        guard self.url == url, self.isbn13 == isbn13 else {
            return Self.initialPhase(url: url, isbn13: isbn13, pipeline: pipeline)
        }
        return currentPhase
    }

    func load(_ url: URL?, isbn: String? = nil) async {
        let id = UUID()
        requestID = id
        self.url = url
        let isbn13 = BookISBN.isbn13(from: isbn)
        self.isbn13 = isbn13
        currentPhase = Self.initialPhase(url: url, isbn13: isbn13, pipeline: pipeline)
        guard case .loading = currentPhase else { return }
        do {
            let image = try await BookCoverSource.load(
                url: url, isbn13: isbn13, lookupYes24: lookupYes24, loadImage: pipeline.image(for:)
            )
            try Task.checkCancellation()
            guard requestID == id else { return }
            currentPhase = .loaded(image)
        } catch {
            guard !Task.isCancelled, requestID == id else { return }
            currentPhase = BookCoverFailure.isUnavailable(error) ? .unavailable : .failed
        }
    }

    private static func initialPhase(url: URL?, isbn13: String?, pipeline: SharedImageLoader<Image>) -> Phase {
        guard let url else { return isbn13 == nil ? .unavailable : .loading }
        guard BookCoverSource.usesProvidedURLFirst(url, isbn13: isbn13),
              let image = pipeline.cachedImage(for: url) else { return .loading }
        return .loaded(image)
    }
}
