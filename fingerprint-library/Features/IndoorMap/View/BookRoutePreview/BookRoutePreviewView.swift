import ComposableArchitecture
import SwiftUI

/// PLI-96 / #116. 이전 화면의 도서를 받고, 버튼으로만 테스트 목적지로 전환한다.
struct BookRoutePreviewView: View {
    @State private var routeStore = Store(
        initialState: BookRoutePreviewFeature.State()
    ) {
        BookRoutePreviewFeature()
    }
    
    @State private var destination: BookRoutePreviewDestination
    @State private var destinationStore: StoreOf<BookShelfMapFeature>?
    @State private var navigationFlow = BookRoutePreviewNavigationState()
    @State private var routeFloorID: UUID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var previewSession: BookNavigationSession? {
        routeStore.previewSession
    }
    
    private var isLoadingRoute: Bool {
        routeStore.isLoadingRoute
    }

    private var routeError: String? {
        routeStore.routeError
    }
    
    private let accent = Color(red: 0.88, green: 0.95, blue: 0.19)
    private var routeRequest: BookRoutePreviewRequest { .init(state: destinationStore?.state) }
    private var readySession: BookNavigationSession? {
        guard let previewSession, case let .ready(map, labels, stops) = routeRequest,
              previewSession.map == map, previewSession.shelfLabels == labels,
              previewSession.stops.count == stops.count,
              previewSession.stops.allSatisfy({ stops.contains($0) }) else { return nil }
        return previewSession
    }
    private var orderedBooks: [Book] { readySession?.stops.map(\.book) ?? destination.books }

    init(books: [Book] = []) {
        let destination = BookRoutePreviewDestination(books: books)
        _destination = State(initialValue: destination)
        _destinationStore = State(initialValue: Self.makeStore(for: destination))
    }

    static func makeShelfMapState(for destination: BookRoutePreviewDestination) -> BookShelfMapFeature.State? {
        guard var state = BookShelfMapFeature.State(books: destination.books) else { return nil }
        if destination.isTestMode {
            for item in BookRoutePreviewSample.testItems {
                state.holdings[item.book.id] = .loaded([item.holding])
            }
        }
        return state
    }

    private static func makeStore(for destination: BookRoutePreviewDestination) -> StoreOf<BookShelfMapFeature>? {
        makeShelfMapState(for: destination).map { state in
            Store(initialState: state) { BookShelfMapFeature() }
        }
    }

    var body: some View {
        BookRoutePreviewMapSheet(onBack: { dismiss() }, onViewportChange: {
            if previewSession == nil { destinationStore?.send(.focusShelfTapped) }
        }) { insets, cameraRevision in
            Group {
                if let previewSession,
                   let floor = previewSession.map.floors.first(where: { $0.id == (routeFloorID ?? previewSession.origin.floorID) }) {
                    IndoorMapKitView(
                        map: previewSession.map, floor: floor, selectedFeatureID: nil,
                        position: previewSession.start, showsUserLocation: false, isPlacingOrigin: false,
                        cameraRequest: .init(id: cameraRevision * 100 + floor.ordinal, target: .route(previewSession.route,
                            featureIDs: [previewSession.origin.mapElementID] + previewSession.stops.map { $0.shelf.mapElementID })),
                        onSelect: { _ in }, onPlaceOrigin: { _ in },
                        route: previewSession.route,
                        groupTransitionNodes: previewSession.guidance.groupTransitionNodes,
                        viewportInsets: insets,
                        shelfLabels: previewSession.shelfLabels,
                        highlightedFeatureIDs: Set(previewSession.stops.map { $0.shelf.mapElementID })
                    )
                    .accessibilityIdentifier("preview-test-route-map")
                } else if let destinationStore {
                    IndoorMapView(
                        store: destinationStore.scope(state: \.map, action: \.map),
                        showsDestinationCard: false,
                        bottomContentInset: insets.bottom,
                        highlightedFeatureIDs: destinationStore.highlightedFeatureIDs,
                        showsCurrentLocationButton: false,
                        extendsUnderBottomSafeArea: true
                    )
                } else {
                    ContentUnavailableView(
                        destination.books.isEmpty ? "목적지 도서를 기다리고 있어요" : "목적지 정보를 확인해 주세요",
                        systemImage: "books.vertical",
                        description: Text(destination.books.isEmpty
                            ? "도서 목록을 전달하거나 아래 테스트 버튼을 눌러 주세요."
                            : "서가 조회는 ID가 서로 다른 1~\(BookRouteSelection.maximumBookCount)권을 지원해요.")
                    )
                    .padding(.bottom, insets.bottom)
                }
            }
        } details: {
            VStack(spacing: 0) {
                Text("경로 미리보기")
                    .font(.headline)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                Button("테스트모드") {
                    destinationStore?.send(.map(.disappeared))
                    
                    routeStore.send(.reset)
                    routeFloorID = nil
                    
                    destination.useTestMode()
                    destinationStore = Self.makeStore(for: destination)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("preview-test-mode")
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
            .fullScreenCover(item: $navigationFlow.session, onDismiss: {
                if navigationFlow.presentationDismissed() { dismiss() }
            }) { session in
                BookNavigationView(session: session) { _ in
                    navigationFlow.navigationEnded()
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .overlay(alignment: .topTrailing) {
            if let previewSession {
                Menu("층 보기", systemImage: "square.3.layers.3d") {
                    ForEach(previewSession.map.floors) { floor in
                        Button("\(floor.ordinal + 1)층") { routeFloorID = floor.id }
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(16)
            }
        }
        .accessibilityIdentifier("book-route-preview")
        .task(id: destinationStore.map { ObjectIdentifier($0) }) { [destinationStore] in
            // Store 교체 시 기존 로딩 task를 취소해 이전 도서의 응답을 분리한다.
            guard let destinationStore else { return }
            await destinationStore.send(.task).finish()
        }
        .task(id: routeRequest) {
            let request = routeRequest
            routeFloorID = nil

            await routeStore.send(.requestChanged(request)).finish()
        }
        .onDisappear {
            routeStore.send(.disappeared)
            destinationStore?.send(.map(.disappeared))
        }
    }

    private var routeMetrics: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(spacing: 12))

        return VStack(alignment: .leading, spacing: 8) {
            if destination.isTestMode {
                Text("고정 목데이터 · 도서 3권 최단 방문 순서 테스트")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("preview-test-mode-status")
            }
            if destinationStore != nil, previewSession == nil, routeError == nil {
                ProgressView(isLoadingRoute ? "311-B에서 목적지까지 경로 계산 중" : "도서·서가 위치 확인 중")
                    .font(.caption)
            }
            if let routeError {
                Text(routeError).font(.caption).foregroundStyle(.red)
                    .accessibilityIdentifier("preview-test-route-error")
            }
            if let previewSession {
                Text("311-B → " + previewSession.stops.map { "\($0.shelf.realNumber)-\($0.shelf.side.rawValue)" }.joined(separator: " → "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            layout {
                HStack(spacing: 12) {
                    metric("도보", unit: "min", value: previewSession.map {
                        $0.guidance.walkingMinutes.formatted(.number.precision(.fractionLength(2)))
                    })
                    metric("단계", unit: "steps", value: previewSession.map { String($0.guidance.stepCount) })
                    metric("거리", unit: "m", value: previewSession.map { $0.route.distanceMeters.formatted(.number.precision(.fractionLength(0))) })
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("출발") { navigationFlow.start(readySession) }
                    .font(.headline)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.large)
                    .fixedSize()
                    .disabled(readySession == nil || isLoadingRoute || routeError != nil)
                    .accessibilityIdentifier("book-route-preview-start")
                    .accessibilityHint("계산한 경로 정보를 실시간 길안내 개발용 화면으로 전달해요")
            }
            .padding(16)
            .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 20))

            Text(previewSession == nil ? "경로 계산 후 시간·단계·거리가 표시돼요."
                 : "시속 5km 기준 예상 시간이에요(10m ≈ 7.2초). 단계는 그룹 전환 횟수 + 1이며, 주황색 원은 전환 노드예요. 모든 방문 순서 중 실제 이동거리가 가장 짧은 경로예요. 출발점은 테스트용 고정 위치예요.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func metric(_ title: String, unit: String, value: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value ?? "—").font(.title2.bold())
                Text(unit).font(.caption)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.map { "\(title), \($0) \(unit)" } ?? "\(title), 계산 전")
    }

    private var routeSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("경로 요약").font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                Label("출발 · 3층 311-B (테스트 고정)", systemImage: "location.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .blue)
                Divider().padding(.leading, 28)
                if destination.books.isEmpty {
                    Text("전달받은 목적지 도서가 없어요").foregroundStyle(.secondary)
                } else if destinationStore != nil {
                    ForEach(Array(orderedBooks.enumerated()), id: \.element.id) { index, book in
                        Label("\(index + 1). \(BookText.plainText(book.title))", systemImage: "book.circle.fill")
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
                VStack(spacing: 0) {
                    ForEach(orderedBooks) { book in
                        if book.id != orderedBooks.first?.id {
                            Divider().padding(.leading, 104).padding(.trailing, 16)
                        }
                        HStack(alignment: .top, spacing: 16) {
                            BookCoverView(url: book.imageURL, isbn: book.isbn)
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
                    }
                }
                .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
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
