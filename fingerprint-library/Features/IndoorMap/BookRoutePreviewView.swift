import ComposableArchitecture
import SwiftUI

/// PLI-96 / #116. 이전 화면의 도서를 받고, 버튼으로만 테스트 목적지로 전환한다.
struct BookRoutePreviewView: View {
    @State private var destination: BookRoutePreviewDestination
    @State private var destinationStore: StoreOf<BookShelfMapFeature>?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let accent = Color(red: 0.88, green: 0.95, blue: 0.19)

    init(books: [Book] = []) {
        let destination = BookRoutePreviewDestination(books: books)
        _destination = State(initialValue: destination)
        _destinationStore = State(initialValue: Self.makeStore(for: destination))
    }

    static func makeShelfMapState(for destination: BookRoutePreviewDestination) -> BookShelfMapFeature.State? {
        guard var state = BookShelfMapFeature.State(books: destination.books) else { return nil }
        if destination.isAnimalFarmTest {
            state.holdings[BookRoutePreviewSample.book.id] = .loaded([BookRoutePreviewSample.holding])
        }
        return state
    }

    private static func makeStore(for destination: BookRoutePreviewDestination) -> StoreOf<BookShelfMapFeature>? {
        makeShelfMapState(for: destination).map { state in
            Store(initialState: state) { BookShelfMapFeature() }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let panelHeight = geometry.size.height * 0.57
            ZStack(alignment: .bottom) {
                Group {
                    if let destinationStore {
                        IndoorMapView(
                            store: destinationStore.scope(state: \.map, action: \.map),
                            showsDestinationCard: false,
                            highlightedFeatureIDs: destinationStore.highlightedFeatureIDs,
                            showsCurrentLocationButton: false,
                            extendsUnderBottomSafeArea: false
                        )
                    } else {
                        ContentUnavailableView(
                            destination.books.isEmpty ? "목적지 도서를 기다리고 있어요" : "목적지 정보를 확인해 주세요",
                            systemImage: "books.vertical",
                            description: Text(destination.books.isEmpty
                                ? "도서 목록을 전달하거나 아래 테스트 버튼을 눌러 주세요."
                                : "서가 조회는 ID가 서로 다른 1~\(BookRouteSelection.maximumBookCount)권을 지원해요.")
                        )
                    }
                }
                .frame(height: geometry.size.height - panelHeight)
                .frame(maxHeight: .infinity, alignment: .top)

                VStack(spacing: 0) {
                    header
                    Button("동물농장으로 테스트") {
                        destinationStore?.send(.map(.disappeared))
                        destination.useAnimalFarmTest()
                        destinationStore = Self.makeStore(for: destination)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("animal-farm-test")
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
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
        .task(id: destinationStore.map { ObjectIdentifier($0) }) { [destinationStore] in
            // Store 교체 시 기존 로딩 task를 취소해 이전 도서의 응답을 분리한다.
            guard let destinationStore else { return }
            await destinationStore.send(.task).finish()
        }
        .onDisappear { destinationStore?.send(.map(.disappeared)) }
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
            if destination.isAnimalFarmTest {
                Text("고정 목데이터 · 동물농장 목적지 테스트")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("animal-farm-test-status")
            }
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
                if destination.books.isEmpty {
                    Text("전달받은 목적지 도서가 없어요").foregroundStyle(.secondary)
                } else if destinationStore != nil {
                    ForEach(destination.books) { book in
                        Label(BookText.plainText(book.title), systemImage: "book.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .orange)
                    }
                } else {
                    Text("전달받은 \(destination.books.count)권 · 목적지 정보 확인 필요")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var bookInformation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("도서 및 청구기호").font(.headline)
            if destinationStore != nil {
                ForEach(destination.books) { book in
                    HStack(alignment: .top, spacing: 16) {
                        BookCoverView(url: book.imageURL)
                            .frame(width: 72, height: 104)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 6) {
                            Text(BookText.plainText(book.title))
                                .font(.subheadline.bold())
                                .fixedSize(horizontal: false, vertical: true)
                            Text(BookText.plainText(book.author))
                                .font(.caption).foregroundStyle(.secondary)
                            holdingInformation(for: book)
                            ForEach(destinationStore?.state.shelves(for: book.id) ?? []) { shelf in
                                Text("서가 \(shelf.realNumber)-\(shelf.side.rawValue)")
                                    .font(.caption.bold()).foregroundStyle(.orange)
                            }
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

    @ViewBuilder
    private func holdingInformation(for book: Book) -> some View {
        switch destinationStore?.holdings[book.id] {
        case nil, .loading:
            ProgressView("소장 위치 확인 중").font(.caption)
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.secondary)
            Button("소장 위치 다시 확인") {
                destinationStore?.send(.retryHoldingsTapped(book.id))
            }
            .font(.caption)
        case .loaded(let holdings):
            if holdings.isEmpty {
                Text("소장 위치 정보가 없어요").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(holdings) { holding in
                VStack(alignment: .leading, spacing: 4) {
                    if let location = holding.locationName { Text(location) }
                    if let callNumber = holding.callNumber { Text(callNumber).textSelection(.enabled) }
                    Text(holding.availabilityText).foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }
}

#Preview("도서 입력 대기 · 다크 모드") {
    NavigationStack {
        BookRoutePreviewView()
    }
}
