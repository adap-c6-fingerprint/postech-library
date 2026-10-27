import SwiftUI
import UIKit

struct BookCoverView: View {
    let url: URL?
    @State private var model: BookCoverModel

    init(url: URL?) {
        self.url = url
        _model = State(initialValue: BookCoverModel(url: url))
    }

    var body: some View {
        ZStack {
            switch model.phase(for: url) {
            case let .loaded(image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            case .loading:
                ProgressView()
            case .failed:
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("표지 오류").font(.caption2)
                }
                .foregroundStyle(.secondary)
            case .unavailable:
                Image(systemName: "book.closed")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) { await model.load(url) }
    }
}

@MainActor
@Observable
final class BookCoverModel {
    enum Phase {
        case loading
        case loaded(UIImage)
        case failed
        case unavailable
    }

    private var url: URL?
    private var currentPhase: Phase
    private let pipeline: SharedImageLoader<UIImage>

    init(url: URL?, pipeline: SharedImageLoader<UIImage>? = nil) {
        self.url = url
        let pipeline = pipeline ?? BookCoverPipeline.shared
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
            guard self.url == url else { return }
            currentPhase = .loaded(image)
        } catch {
            guard !Task.isCancelled, self.url == url else { return }
            currentPhase = .failed
        }
    }
}
