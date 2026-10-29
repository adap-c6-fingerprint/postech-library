import ComposableArchitecture
import SwiftUI

struct BookShelfMapView: View {
    let store: StoreOf<BookShelfMapFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        IndoorMapView(
            store: store.scope(state: \.map, action: \.map),
            showsDestinationCard: false,
            highlightedFeatureIDs: store.highlightedFeatureIDs,
            showsCurrentLocationButton: false,
            extendsUnderBottomSafeArea: false
        )
        .safeAreaInset(edge: .bottom, spacing: 0) { shelfCard }
        .navigationTitle("서가 위치")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("뒤로", systemImage: "chevron.left") { dismiss() }
                    .accessibilityIdentifier("book-shelf-map-back")
            }
        }
        .task { await store.send(.task).finish() }
    }

    private var shelfCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(store.books.count == 1 ? BookText.plainText(store.books[0].title) : "\(store.books.count)권의 서가 위치")
                    .font(.headline).lineLimit(2)
                Spacer()
                if !store.state.shelves.isEmpty {
                    Button("모두 보기") { store.send(.focusShelfTapped) }.font(.subheadline)
                }
            }
            Text("도서관 소장 정보 기준 · 대출 상태와 실제 배가 상태는 다를 수 있어요")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(store.books) { book in
                        VStack(alignment: .leading, spacing: 8) {
                            if store.books.count > 1 {
                                Text(BookText.plainText(book.title)).font(.subheadline.weight(.semibold)).lineLimit(2)
                            }
                            holdingsContent(for: book)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 180)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func holdingsContent(for book: Book) -> some View {
        switch store.holdings[book.id] {
        case nil, .loading:
            ProgressView("도서 위치를 확인하고 있어요")
        case .failed(let message):
            Text(message).font(.subheadline).foregroundStyle(.secondary)
            if BookHoldingsClient.recordID(for: book) != nil {
                Button("다시 시도") { store.send(.retryHoldingsTapped(book.id)) }.buttonStyle(.bordered)
            }
        case .loaded(let holdings):
            if holdings.isEmpty {
                Text("이 책의 소장 위치 정보가 없어요.").font(.subheadline).foregroundStyle(.secondary)
            } else if store.map.isLoading || store.map.isLoadingShelfLabels {
                ProgressView("서가 위치를 확인하고 있어요")
            } else if store.map.loadError == nil, store.map.shelfLabelError == nil {
                ForEach(store.resolutions[book.id] ?? []) { resolution in
                    holdingContent(resolution, bookID: book.id)
                }
            }
        }
    }

    private func holdingContent(_ resolution: BookHoldingShelfResolution, bookID: Book.ID) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(resolution.holding.locationName ?? resolution.holding.locationCode ?? "소장 위치 확인 필요")
                .font(.subheadline.weight(.medium))
            if let call = resolution.holding.callNumber { Text(call).font(.subheadline).textSelection(.enabled) }
            Text(resolution.holding.availabilityText).font(.caption).foregroundStyle(.secondary)
            switch resolution.outcome {
            case .unsupportedLocation:
                Text("아직 지도에 연결되지 않은 소장 위치예요.").font(.caption).foregroundStyle(.secondary)
            case .missingCallNumber:
                Text("청구기호 정보가 없어 서가를 찾을 수 없어요.").font(.caption).foregroundStyle(.secondary)
            case .outsideIndex:
                Text("청구기호와 일치하는 서가를 찾지 못했어요.").font(.caption).foregroundStyle(.secondary)
            case .candidates(let shelves):
                if shelves.count > 1 {
                    Text("범위가 겹치는 후보 서가 \(shelves.count)곳을 표시했어요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(shelves) { shelf in
                    Button {
                        store.send(.candidateTapped(bookID, fixtureNumber: shelf.fixtureNumber))
                    } label: {
                        let floor = store.map.map?.floors.first { $0.id == shelf.floorID }
                        Label("\(floor.map { "\($0.ordinal + 1)층" } ?? "층 확인 필요") · 서가 \(shelf.realNumber)-\(shelf.side.rawValue)",
                              systemImage: "mappin.circle.fill")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered).tint(.orange)
                    .accessibilityIdentifier("book-shelf-\(bookID)-\(shelf.fixtureNumber)")
                }
            }
        }
    }
}
