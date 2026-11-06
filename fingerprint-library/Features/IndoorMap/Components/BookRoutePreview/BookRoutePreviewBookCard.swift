import ComposableArchitecture
import SwiftUI

/// 선택한 책의 소장 위치·경로 정보와 소개를 보여 주는 가로 페이징 카드.
struct BookRoutePreviewBookCard: View {
    let book: Book
    let holdings: BookShelfMapFeature.HoldingsState?
    let resolutions: [BookHoldingShelfResolution]
    let map: IndoorMap?
    let session: BookNavigationSession?
    let onRetryHoldings: () -> Void

    @State private var detailStore: StoreOf<BookDetailFeature>
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(book: Book, holdings: BookShelfMapFeature.HoldingsState?,
         resolutions: [BookHoldingShelfResolution], map: IndoorMap?,
         session: BookNavigationSession?, onRetryHoldings: @escaping () -> Void) {
        self.book = book
        self.holdings = holdings
        self.resolutions = resolutions
        self.map = map
        self.session = session
        self.onRetryHoldings = onRetryHoldings
        _detailStore = State(initialValue: Store(initialState: BookDetailFeature.State(book: book)) {
            BookDetailFeature()
        })
    }

    private var stop: BookNavigationStop? {
        session?.stops.first { $0.book.id == book.id }
    }

    private var holding: BookHolding? {
        if let shelf = stop?.shelf,
           let resolution = resolutions.first(where: { $0.shelves.contains(shelf) }) {
            return resolution.holding
        }
        guard case let .loaded(items) = holdings else { return nil }
        return BookHoldingPresentation.preferred(in: items)
    }

    private var shelves: [IndoorShelfLabel] {
        stop?.candidateShelves ?? resolutions.flatMap(\.shelves)
    }

    private var location: String? {
        guard let holding else { return nil }
        let floorID = stop?.shelf.floorID ?? shelves.first?.floorID
        let floor = map?.floors.first { $0.id == floorID }
        return BookDetailDestinationPresentation(
            holding: holding, floorText: floor.map { "\($0.ordinal + 1)층" }, shelves: shelves
        ).locationText
    }

    private var routeSummary: String? {
        guard let session, let index = session.stops.firstIndex(where: { $0.book.id == book.id }) else { return nil }
        let legs = session.legs.prefix(index + 1)
        let distance = legs.reduce(0) { $0 + $1.distanceMeters }
        let floorChanges = legs.reduce(0) { $0 + $1.floorChanges.count }
        let estimated = legs.contains { $0.usesEstimatedDistances } ? "약 " : ""
        return "\(estimated)\(distance.formatted(.number.precision(.fractionLength(0))))m · 층 이동 \(floorChanges)회"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
                layout {
                    BookCoverView(url: book.imageURL, isbn: book.isbn)
                        .frame(width: 140, height: 186)
                        .background(.quaternary, in: .rect(cornerRadius: 6))
                        .clipShape(.rect(cornerRadius: 6))
                    bibliography
                }
                description
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("multiBookPreview.card.\(book.id)")
        .task {
            // Store가 조회를 소유하므로 페이지를 넘겨도 완료된 소개를 재요청하지 않는다.
            if book.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                detailStore.send(.loadDescription)
            }
        }
    }

    private var bibliography: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch holdings {
            case nil, .loading:
                ProgressView("소장 위치 확인 중").font(.caption)
            case .failed:
                Text("소장 위치 확인 실패").font(.caption)
                Button("다시 시도", action: onRetryHoldings).font(.caption)
            case .loaded:
                Text(holding?.availabilityText ?? "소장정보 없음")
                    .typography(.caption2)
                    .foregroundStyle(holding?.availability == "available" ? Color.green : Color.textTertiary)
            }
            Text(BookText.plainText(book.title))
                .typography(.bookTitle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let location { Text(location).typography(.body2) }
            if let callNumber = holding?.callNumber {
                Text(callNumber).typography(.body2).textSelection(.enabled)
            }
            if let routeSummary {
                Text(routeSummary)
                    .typography(.caption1)
                    .foregroundStyle(Color.textTertiary)
                    .accessibilityLabel("경로 시작부터 이 책까지 \(routeSummary)")
            } else if holding != nil && shelves.isEmpty {
                Text("안내할 서가 위치를 확인할 수 없어요.")
                    .font(.caption).foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 6) {
            let author = BookText.plainText(book.author).trimmingCharacters(in: .whitespacesAndNewlines)
            if !author.isEmpty { Text("\(author) 저자").typography(.body2) }
            Group {
                if let summary = book.description, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(BookText.plainText(summary))
                } else if detailStore.isLoading || !detailStore.hasLoaded {
                    ProgressView("책 소개를 불러오고 있어요")
                } else if let message = detailStore.errorMessage {
                    Text(message)
                    if detailStore.isbn13 != nil {
                        Button("다시 시도") { detailStore.send(.retryButtonTapped) }
                    }
                } else if let description = detailStore.description {
                    Text(description.text)
                    Link("책 소개 제공: Yes24 · 원문 보기", destination: description.sourceURL)
                } else {
                    Text("이 책의 소개가 아직 제공되지 않아요.")
                }
            }
            .typography(.caption1)
            .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
