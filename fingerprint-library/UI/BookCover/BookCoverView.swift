import SwiftUI
import UIKit

struct BookCoverView<CoverModifier: ViewModifier>: View {
    let url: URL?
    let isbn: String?
    let cachedURL: URL?
    let onOpen: (() -> Void)?
    let allowsRetry: Bool
    let imageCornerRadius: CGFloat
    let fitAlignment: Alignment?
    let placeholderAspectRatio: CGFloat?
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
        fitAlignment: Alignment? = nil,
        placeholderAspectRatio: CGFloat? = nil,
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
        self.fitAlignment = fitAlignment
        self.placeholderAspectRatio = placeholderAspectRatio
        self.coverModifier = coverModifier
        self.lookupLegacyOriginal = lookupLegacyOriginal
        self.onCoverRecovered = onCoverRecovered
        _model = State(initialValue: BookCoverModel(url: url, isbn: isbn, cachedURL: cachedURL, pipeline: BookCoverPipeline.shared,
            lookupYes24: { try await BookCoverPipeline.yes24Cover.url(for: $0) }))
    }

    var body: some View {
        Group {
            if let fitAlignment {
                BookCoverFitLayout(aspectRatio: fitAspectRatio, alignment: fitAlignment) {
                    interactiveContent.modifier(coverModifier)
                }
            } else {
                interactiveContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .modifier(coverModifier)
            }
        }
        .task(id: LoadID(url: url, isbn13: BookISBN.isbn13(from: isbn), cachedURL: cachedURL, retry: retryID)) {
            await model.load(
                url, isbn: isbn, cachedURL: cachedURL,
                lookupLegacyOriginal: lookupLegacyOriginal, onCoverRecovered: onCoverRecovered
            )
        }
    }

    private var fitAspectRatio: CGFloat? {
        if case let .loaded(image) = model.phase(for: url, isbn: isbn, cachedURL: cachedURL) {
            return BookCoverFit.aspectRatio(of: image.size) ?? placeholderAspectRatio
        }
        return placeholderAspectRatio
    }

    private var interactiveContent: some View {
        Group {
            if isRetryable(model.phase(for: url, isbn: isbn, cachedURL: cachedURL)), allowsRetry {
                Button { retryID += 1 } label: {
                    if case .offline = model.phase(for: url, isbn: isbn, cachedURL: cachedURL) {
                        offlineNotice
                    } else {
                        fallbackCover
                    }
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
        case .offline:
            offlineNotice
        }
    }

    private func isRetryable(_ phase: BookCoverModel<UIImage>.Phase) -> Bool {
        switch phase {
        case .failed, .offline: true
        case .loaded, .loading, .unavailable: false
        }
    }

    /// 표지가 없거나 불러오지 못했을 때 보여주는 기본 표지.
    private var fallbackCover: some View {
        Image(.bookCover).resizable().scaledToFit()
            .clipShape(.rect(cornerRadius: imageCornerRadius))
            .accessibilityLabel("기본 책 표지")
    }

    private var offlineNotice: some View {
        Text("연결 없음")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
    }
    // 기기가 서버에 닿지 못한 경우에만 쓴다. 기본 표지와 구분하려고 아이콘 없이 문구만 보인다.

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
        fitAlignment: Alignment? = nil, placeholderAspectRatio: CGFloat? = nil,
        lookupLegacyOriginal: (() async throws -> URL?)? = nil,
        onCoverRecovered: ((URL) -> Void)? = nil
    ) {
        self.init(
            url: url, isbn: isbn, cachedURL: cachedURL, onOpen: onOpen, allowsRetry: allowsRetry,
            imageCornerRadius: imageCornerRadius, fitAlignment: fitAlignment,
            placeholderAspectRatio: placeholderAspectRatio, lookupLegacyOriginal: lookupLegacyOriginal, onCoverRecovered: onCoverRecovered, coverModifier: EmptyModifier()
        )
    }
}
