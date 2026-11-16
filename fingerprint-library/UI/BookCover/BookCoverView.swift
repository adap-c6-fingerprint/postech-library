import SwiftUI
import UIKit

struct BookCoverView<CoverModifier: ViewModifier>: View {
    let url: URL?
    let isbn: String?
    let cachedURL: URL?
    let onOpen: (() -> Void)?
    let allowsRetry: Bool
    let imageCornerRadius: CGFloat
    private let coverModifier: CoverModifier
    private let lookupLegacyOriginal: (() async throws -> URL?)?
    private let onCoverRecovered: ((URL) -> Void)?
    @State private var retryID = 0
    @State private var model: BookCoverModel<UIImage>

    init(
        url: URL?,
        isbn: String? = nil,
        cachedURL: URL? = nil,
        onOpen: (() -> Void)? = nil,
        allowsRetry: Bool = true,
        imageCornerRadius: CGFloat = 0,
        lookupLegacyOriginal: (() async throws -> URL?)? = nil,
        onCoverRecovered: ((URL) -> Void)? = nil,
        coverModifier: CoverModifier
    ) {
        self.url = url
        self.isbn = isbn
        self.cachedURL = cachedURL
        self.onOpen = onOpen
        self.allowsRetry = allowsRetry
        self.imageCornerRadius = imageCornerRadius
        self.coverModifier = coverModifier
        self.lookupLegacyOriginal = lookupLegacyOriginal
        self.onCoverRecovered = onCoverRecovered
        _model = State(initialValue: BookCoverModel(url: url, isbn: isbn, cachedURL: cachedURL, pipeline: BookCoverPipeline.shared,
            lookupYes24: { try await BookCoverPipeline.yes24Cover.url(for: $0) }))
    }

    var body: some View {
        Group {
            if case .failed = model.phase(for: url, isbn: isbn, cachedURL: cachedURL), allowsRetry {
                Button { retryID += 1 } label: {
                    fallbackCover
                }
                .accessibilityLabel("표지 다시 불러오기")
            } else if let onOpen {
                Button(action: onOpen) { coverContent }
                    .accessibilityLabel("책 표지, 책 소개 보기")
            } else {
                coverContent
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(coverModifier)
        .task(id: LoadID(url: url, isbn13: BookISBN.isbn13(from: isbn), cachedURL: cachedURL, retry: retryID)) {
            await model.load(
                url, isbn: isbn, cachedURL: cachedURL,
                lookupLegacyOriginal: lookupLegacyOriginal, onCoverRecovered: onCoverRecovered
            )
        }
    }

    @ViewBuilder
    private var coverContent: some View {
        switch model.phase(for: url, isbn: isbn, cachedURL: cachedURL) {
        case let .loaded(image):
            Image(uiImage: image).resizable().scaledToFit()
                .clipShape(.rect(cornerRadius: imageCornerRadius))
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed, .unavailable:
            fallbackCover
        }
    }

    /// 표지가 없거나 불러오지 못했을 때 보여주는 기본 표지.
    private var fallbackCover: some View {
        Image(.bookCover).resizable().scaledToFit()
            .clipShape(.rect(cornerRadius: imageCornerRadius))
            .accessibilityLabel("기본 책 표지")
    }

    private struct LoadID: Equatable {
        let url: URL?
        let isbn13: String?
        let cachedURL: URL?
        let retry: Int
    }
}

extension BookCoverView where CoverModifier == EmptyModifier {
    init(
        url: URL?, isbn: String? = nil, cachedURL: URL? = nil, onOpen: (() -> Void)? = nil,
        allowsRetry: Bool = true, imageCornerRadius: CGFloat = 0,
        lookupLegacyOriginal: (() async throws -> URL?)? = nil,
        onCoverRecovered: ((URL) -> Void)? = nil
    ) {
        self.init(
            url: url, isbn: isbn, cachedURL: cachedURL, onOpen: onOpen, allowsRetry: allowsRetry,
            imageCornerRadius: imageCornerRadius, lookupLegacyOriginal: lookupLegacyOriginal, onCoverRecovered: onCoverRecovered, coverModifier: EmptyModifier()
        )
    }
}
