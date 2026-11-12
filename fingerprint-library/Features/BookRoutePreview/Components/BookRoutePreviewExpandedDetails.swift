import ComposableArchitecture
import SwiftUI

struct BookRoutePreviewExpandedDetails: View {
    let book: Book
    let holdings: BookShelfMapFeature.HoldingsState?
    let info: BookRoutePreviewBookInfo
    let detailStore: StoreOf<BookDetailFeature>
    let onRetryHoldings: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled

    private var usesAccessibleLayout: Bool { dynamicTypeSize.isAccessibilitySize || isVoiceOverEnabled }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                holdingStatus
                Text(BookText.plainText(book.title))
                    .typography(.bookTitle)
                    .lineLimit(usesAccessibleLayout ? nil : 2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                location
                routeSummary
            }
            BookRoutePreviewDescription(book: book, detailStore: detailStore, style: .expanded)
                .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("multiBookPreview.expandedDetails.\(book.id)")
        .task(id: book.id) {
            if book.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                detailStore.send(.loadDescription)
            }
        }
    }

    @ViewBuilder
    private var holdingStatus: some View {
        switch holdings {
        case nil, .loading:
            ProgressView("소장 위치 확인 중").typography(.caption2)
        case .failed:
            HStack(spacing: 8) {
                Text("소장 위치 확인 실패")
                Button("다시 시도", action: onRetryHoldings)
            }
            .typography(.caption2)
        case .loaded:
            Text(info.holding?.availabilityText ?? "소장정보 없음")
                .typography(.caption2)
                .foregroundStyle(info.holding?.availability == "available" ? Color.green : Color.textTertiary)
        }
    }

    @ViewBuilder
    private var location: some View {
        if info.location != nil || info.holding?.callNumber != nil {
            VStack(alignment: .leading, spacing: 2) {
                if let location = info.location { Text(location) }
                if let callNumber = info.holding?.callNumber {
                    Text(callNumber).textSelection(.enabled)
                }
            }
            .typography(.body1)
        }
    }

    @ViewBuilder
    private var routeSummary: some View {
        if let route = info.route {
            BookExpandedRouteSummary(distanceText: route.distanceText, floorChangeCount: route.floorChangeCount)
                .padding(.top, 2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("경로 시작부터 이 책까지 이동 거리 \(route.distanceText), 층 이동 \(route.floorChangeCount)회")
        } else if info.holding != nil && info.shelves.isEmpty {
            Text("안내할 서가 위치를 확인할 수 없어요.")
                .typography(.caption1)
                .foregroundStyle(Color.textTertiary)
        }
    }
}
