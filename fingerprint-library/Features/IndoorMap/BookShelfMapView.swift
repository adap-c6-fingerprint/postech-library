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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            shelfCard
        }
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
                Text(store.books.count == 1
                     ? BookText.plainText(store.books[0].title)
                     : "\(store.books.count)권의 서가 위치")
                    .font(.headline)
                    .lineLimit(2)
                if store.books.count > 1 {
                    Spacer()
                    Button("모두 보기") { store.send(.focusShelfTapped) }
                        .font(.subheadline)
                }
            }

            Text("임시 서가 위치 · 실제 도서 위치와 연결 전입니다")
                .font(.caption)
                .foregroundStyle(.secondary)

            if store.map.isLoading || store.map.isLoadingShelfLabels {
                ProgressView("서가 위치를 확인하고 있어요")
            } else if store.map.loadError == nil, store.map.shelfLabelError == nil {
                ForEach(store.books) { book in
                    if let shelf = store.state.shelf(for: book.id) {
                        Button {
                            store.send(.bookShelfTapped(book.id))
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                if store.books.count > 1 {
                                    Text(BookText.plainText(book.title))
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                Label("3층 · 서가 \(shelf.realNumber)-\(shelf.side.rawValue)",
                                      systemImage: "mappin.circle.fill")
                                    .font(.subheadline)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .accessibilityIdentifier("book-shelf-\(book.id)")
                    } else {
                        Text("\(BookText.plainText(book.title))의 서가 위치를 확인하지 못했어요.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }
}
