import SwiftUI
import UIKit

struct BookCoverView: View {
    let url: URL?
    let isbn: String?
    let onOpen: (() -> Void)?
    let allowsRetry: Bool
    @State private var retryID = 0
    @State private var model: BookCoverModel<UIImage>

    init(url: URL?, isbn: String? = nil, onOpen: (() -> Void)? = nil, allowsRetry: Bool = true) {
        self.url = url
        self.isbn = isbn
        self.onOpen = onOpen
        self.allowsRetry = allowsRetry
        _model = State(initialValue: BookCoverModel(url: url, isbn: isbn, pipeline: BookCoverPipeline.shared,
            fallback: { try await BookCoverPipeline.fallback.coverURL(for: $0) }))
    }

    var body: some View {
        Group {
            if case .failed = model.phase(for: url, isbn: isbn), allowsRetry {
                Button { retryID += 1 } label: {
                    placeholder("arrow.clockwise", text: "다시 시도")
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
        .task(id: LoadID(url: url, isbn13: BookISBN.isbn13(from: isbn), retry: retryID)) { await model.load(url, isbn: isbn) }
    }

    @ViewBuilder
    private var coverContent: some View {
        switch model.phase(for: url, isbn: isbn) {
        case let .loaded(image):
            Image(uiImage: image).resizable().scaledToFit()
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            placeholder("exclamationmark.triangle", text: "로딩 실패")
        case .unavailable:
            placeholder("book.closed", text: "표지 없음")
        }
    }

    private func placeholder(_ symbol: String, text: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.title2)
            Text(text).font(.caption2)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private struct LoadID: Equatable {
        let url: URL?
        let isbn13: String?
        let retry: Int
    }
}
