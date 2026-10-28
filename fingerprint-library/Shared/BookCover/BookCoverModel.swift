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
    private var currentPhase: Phase
    private var requestID: UUID?
    private let pipeline: SharedImageLoader<Image>

    init(url: URL?, pipeline: SharedImageLoader<Image>) {
        self.url = url
        self.pipeline = pipeline
        currentPhase = url.map { url in
            pipeline.cachedImage(for: url).map(Phase.loaded) ?? .loading
        } ?? .unavailable
    }

    func phase(for url: URL?) -> Phase {
        guard self.url == url else {
            return url.flatMap(pipeline.cachedImage).map(Phase.loaded)
                ?? (url == nil ? .unavailable : .loading)
        }
        return currentPhase
    }

    func load(_ url: URL?) async {
        let id = UUID()
        requestID = id
        self.url = url
        guard let url else {
            currentPhase = .unavailable
            return
        }
        if let image = pipeline.cachedImage(for: url) {
            currentPhase = .loaded(image)
            return
        }
        currentPhase = .loading
        do {
            let image = try await pipeline.image(for: url)
            try Task.checkCancellation()
            guard requestID == id else { return }
            currentPhase = .loaded(image)
        } catch {
            guard !Task.isCancelled, requestID == id else { return }
            currentPhase = BookCoverFailure.isUnavailable(error) ? .unavailable : .failed
        }
    }
}
