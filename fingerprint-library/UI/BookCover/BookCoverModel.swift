import Foundation
import Observation

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
    private var cachedURL: URL?
    private var isbn13: String?
    private var currentPhase: Phase
    private var requestID: UUID?
    private let pipeline: SharedImageLoader<Image>
    private let lookupYes24: @Sendable (String) async throws -> URL?

    init(url: URL?, isbn: String? = nil, cachedURL: URL? = nil, pipeline: SharedImageLoader<Image>,
         lookupYes24: @escaping @Sendable (String) async throws -> URL? = { _ in nil }) {
        let isbn13 = BookISBN.isbn13(from: isbn)
        self.url = url
        self.cachedURL = cachedURL
        self.isbn13 = isbn13
        self.pipeline = pipeline
        self.lookupYes24 = lookupYes24
        currentPhase = Self.initialPhase(url: url, isbn13: isbn13, cachedURL: cachedURL, pipeline: pipeline)
    }

    func phase(for url: URL?, isbn: String? = nil, cachedURL: URL? = nil) -> Phase {
        let isbn13 = BookISBN.isbn13(from: isbn)
        guard self.url == url, self.isbn13 == isbn13, self.cachedURL == cachedURL else {
            return Self.initialPhase(url: url, isbn13: isbn13, cachedURL: cachedURL, pipeline: pipeline)
        }
        return currentPhase
    }

    func load(
        _ url: URL?, isbn: String? = nil, cachedURL: URL? = nil,
        lookupLegacyOriginal: (() async throws -> URL?)? = nil,
        onCoverRecovered: ((URL) -> Void)? = nil
    ) async {
        let id = UUID()
        requestID = id
        self.url = url
        self.cachedURL = cachedURL
        let isbn13 = BookISBN.isbn13(from: isbn)
        self.isbn13 = isbn13
        currentPhase = Self.initialPhase(url: url, isbn13: isbn13, cachedURL: cachedURL, pipeline: pipeline)
        guard case .loading = currentPhase else { return }
        do {
            let result = try await BookCoverSource.load(
                url: url, isbn13: isbn13, cachedURL: cachedURL, lookupYes24: lookupYes24,
                lookupLegacyOriginal: lookupLegacyOriginal
            ) { candidate in
                (try await pipeline.image(for: candidate), candidate)
            }
            try Task.checkCancellation()
            guard requestID == id else { return }
            currentPhase = .loaded(result.0)
            if url?.isFileURL == true, !result.1.isFileURL { onCoverRecovered?(result.1) }
        } catch {
            guard !Task.isCancelled, requestID == id else { return }
            currentPhase = BookCoverFailure.isUnavailable(error) ? .unavailable : .failed
        }
    }

    private static func initialPhase(
        url: URL?, isbn13: String?, cachedURL: URL?, pipeline: SharedImageLoader<Image>
    ) -> Phase {
        if let cachedURL, let image = pipeline.cachedImage(for: cachedURL) { return .loaded(image) }
        guard let url else { return isbn13 == nil && cachedURL == nil ? .unavailable : .loading }
        guard BookCoverSource.usesProvidedURLFirst(url, isbn13: isbn13),
              let image = pipeline.cachedImage(for: url) else { return .loading }
        return .loaded(image)
    }
}
