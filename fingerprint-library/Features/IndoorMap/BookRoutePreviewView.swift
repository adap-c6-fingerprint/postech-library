import ComposableArchitecture
import SwiftUI

/// PLI-96 / #116. 실제 IMDF에 고정 목데이터의 목적지 서가만 강조한다.
struct BookRoutePreviewView: View {
    @State private var destinationStore: StoreOf<BookShelfMapFeature>
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let accent = Color(red: 0.88, green: 0.95, blue: 0.19)

    // shortcut: 이번 알파에서는 입력 책 대신 고정 목데이터를 사용한다. 실제 도서 연결 단계에서 해제한다.
    init(books _: [Book]) {
        var state = BookShelfMapFeature.State(book: BookRoutePreviewSample.book)
        // 미리 주어진 소장 정보만 사용하므로 실제 Primo 조회를 하지 않는다.
        state.holdings[BookRoutePreviewSample.book.id] = .loaded([BookRoutePreviewSample.holding])
        _destinationStore = State(initialValue: Store(initialState: state) { BookShelfMapFeature() })
    }

    private var books: [Book] { destinationStore.books }

    var body: some View {
        GeometryReader { geometry in
            let panelHeight = geometry.size.height * 0.57
            ZStack(alignment: .bottom) {
                IndoorMapView(
                    store: destinationStore.scope(state: \.map, action: \.map),
                    showsDestinationCard: false,
                    highlightedFeatureIDs: destinationStore.highlightedFeatureIDs,
                    showsCurrentLocationButton: false,
                    extendsUnderBottomSafeArea: false
                )
                .frame(height: geometry.size.height - panelHeight)
                .frame(maxHeight: .infinity, alignment: .top)

                VStack(spacing: 0) {
                    header
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            routeMetrics
                            routeSummary
                            bookInformation
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                    .scrollIndicators(.hidden)
                }
                .frame(height: panelHeight)
                .frame(maxWidth: .infinity)
                .background {
                    UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .ignoresSafeArea(.container, edges: .bottom)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .accessibilityIdentifier("book-route-preview")
        .task { await destinationStore.send(.task).finish() }
        .onDisappear { destinationStore.send(.map(.disappeared)) }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(.white)
            .accessibilityLabel("뒤로가기")

            Spacer()
            Text("경로 미리보기").font(.headline)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
        .padding(16)
    }

    private var routeMetrics: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(spacing: 12))

        return VStack(alignment: .leading, spacing: 8) {
            Text("고정 목데이터 · 동물농장 목적지 테스트")
                .font(.caption)
                .foregroundStyle(.secondary)
            layout {
                HStack(spacing: 12) {
                    metric("도보", unit: "min")
                    metric("단계", unit: "steps")
                    metric("거리", unit: "m")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("출발") { }
                    .font(.headline)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.large)
                    .fixedSize()
                    .disabled(true)
                    .accessibilityHint("경로 계산 후 사용할 수 있어요")
            }
            .padding(16)
            .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 20))

            Text("경로 계산 후 시간·단계·거리가 표시돼요.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func metric(_ title: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("—").font(.title2.bold())
                Text(unit).font(.caption)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), 계산 전")
    }

    private var routeSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("경로 요약").font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                Label("내 위치", systemImage: "location.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .blue)
                Divider().padding(.leading, 28)
                Label(BookRoutePreviewSample.book.title, systemImage: "book.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var bookInformation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("도서 및 청구기호").font(.headline)
            ForEach(books) { book in
                HStack(alignment: .top, spacing: 16) {
                    BookCoverView(url: book.imageURL)
                        .frame(width: 72, height: 104)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(BookRoutePreviewSample.holding.locationName ?? "")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(BookRoutePreviewSample.holding.callNumber ?? "")
                            .font(.caption).textSelection(.enabled)
                        Text(BookText.plainText(book.title))
                            .font(.subheadline.bold())
                            .fixedSize(horizontal: false, vertical: true)
                        Text(BookText.plainText(book.author))
                            .font(.caption).foregroundStyle(.secondary)
                        if let shelf = destinationStore.state.shelves.first {
                            Text("서가 \(shelf.realNumber)-\(shelf.side.rawValue)")
                                .font(.caption.bold()).foregroundStyle(.orange)
                        }
                        Text("대출 정보 확인 전")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
            }
        }
    }
}

#Preview("한 권 · 다크 모드") {
    NavigationStack {
        BookRoutePreviewView(books: [BookRoutePreviewSample.book])
    }
}
