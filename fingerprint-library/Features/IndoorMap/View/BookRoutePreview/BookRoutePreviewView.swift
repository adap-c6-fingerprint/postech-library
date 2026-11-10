import ComposableArchitecture
import SwiftUI
import UIKit

/// PLI-96 / #116. 이전 화면의 도서를 받고, 버튼으로만 테스트 목적지로 전환한다.
struct BookRoutePreviewView: View {
    enum EntryMode { case preview, direct }

    // 한 권은 바로 안내하고, 여러 권은 책별 서가를 확인한 뒤 안내한다.
    private let entryMode: EntryMode
    @State private var routeStore: StoreOf<BookRoutePreviewFeature>
    
    @State private var destination: BookRoutePreviewDestination
    @State private var destinationStore: StoreOf<BookShelfMapFeature>?
    @State private var navigationFlow = BookRoutePreviewNavigationState()
    @State private var routeFloorID: UUID?
    @State private var previewStart: IndoorPosition?
    /// 사용자가 직접 지정한 출발 위치. 권한이 없거나 실제 위치가 맞지 않을 때 센서 위치 대신 사용한다.
    @State private var manualStart: IndoorPosition?
    @State private var isOriginPickerPresented = false
    /// 위치 권한이 없을 때 보여 주는 알림. 설정 앱의 이 앱 권한 화면으로 보내거나 직접 설정으로 넘긴다.
    @State private var isPermissionAlertPresented = false
    /// 직접 설정으로 넘어가는 중. 지도가 준비되면 출발지 설정 화면을 연다.
    @State private var isPreparingManualOrigin = false
    @Environment(\.indoorRouteMapStore) private var mapStore
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
    private var currentStart: IndoorPosition? {
        // 직접 지정한 출발 위치는 권한·정확도와 무관하게 우선한다.
        if let manualStart { return manualStart }
        guard let mapStore, let position = mapStore.currentPosition,
              position.source == .manual || mapStore.authorization.isAuthorized,
              position.isRecent(at: Date()) else { return nil }
        return position
    }
    private var routeRequest: BookRoutePreviewRequest {
        .init(state: destinationStore?.state, start: previewStart)
    }
    private var readySession: BookNavigationSession? {
        guard let previewSession, case let .ready(map, labels, start, stops) = routeRequest,
              previewSession.map == map, previewSession.shelfLabels == labels,
              previewSession.start == start,
              previewSession.matches(candidates: stops) else { return nil }
        return previewSession
    }
    private var orderedBooks: [Book] { readySession?.stops.map(\.book) ?? destination.books }

    init(books: [Book] = [], entryMode: EntryMode = .preview,
         routeStore: StoreOf<BookRoutePreviewFeature>? = nil) {
        self.entryMode = entryMode
        let destination = BookRoutePreviewDestination(books: books)
        _routeStore = State(initialValue: routeStore ?? Store(initialState: BookRoutePreviewFeature.State()) {
            BookRoutePreviewFeature()
        })
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

    private var previewContent: some View {
        BookRoutePreviewMapSheet(onBack: { dismiss() }, onViewportChange: {
            if previewSession == nil { destinationStore?.send(.focusShelfTapped) }
        }) { insets, cameraRevision in
            Group {
                if let previewSession,
                   let floor = previewSession.map.floors.first(where: { floor in
                       routeFloorID.map { $0 == floor.id }
                           ?? (floor.ordinal == previewSession.start.floorOrdinal)
                   }) {
                    IndoorMapKitView(
                        map: previewSession.map, floor: floor, selectedFeatureID: nil,
                        position: previewSession.start, showsUserLocation: false, isPlacingOrigin: false,
                        cameraRequest: .init(id: cameraRevision * 100 + floor.ordinal, target: .route(previewSession.route,
                            featureIDs: previewSession.stops.flatMap { $0.candidateShelves.map(\.mapElementID) })),
                        onSelect: { _ in }, onPlaceOrigin: { _ in },
                        route: previewSession.route,
                        groupTransitionNodes: previewSession.guidance.groupTransitionNodes,
                        viewportInsets: insets,
                        shelfLabels: previewSession.shelfLabels,
                        highlightedFeatureIDs: Set(previewSession.stops.flatMap { $0.candidateShelves.map(\.mapElementID) })
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
                        systemImage: "book",
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
                    routeStore.send(.analyticsTestModeChanged(true))
                    routeFloorID = nil
                    previewStart = currentStart
                    
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
        }
    }

    /// 준비 중에도 목적지 지도를 깔아 둔다. 권한 알림·출발지 직접 설정·길안내로 이어질 때 화면이 끊기지 않는다.
    private var directContent: some View {
        ZStack {
            directMapBackdrop
            directHeader
            if showsRouteFailure {
                directFailure
            } else {
                directStatus
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("book-navigation-preparing")
    }

    /// 출발 위치를 정하는 동안에는 경로 오류를 띄우지 않는다. 위치가 없어서 나는 오류라 사용자가 할 일이 아니다.
    private var hidesRouteErrorWhileResolvingOrigin: Bool {
        if isPermissionAlertPresented || isOriginPickerPresented || isPreparingManualOrigin { return true }
        return !(mapStore?.authorization.isAuthorized ?? false)
    }

    private var showsRouteFailure: Bool {
        routeError != nil && !hidesRouteErrorWhileResolvingOrigin
    }

    @ViewBuilder
    private var directMapBackdrop: some View {
        if let destinationStore {
            IndoorMapView(
                store: destinationStore.scope(state: \.map, action: \.map),
                showsDestinationCard: false,
                highlightedFeatureIDs: destinationStore.highlightedFeatureIDs,
                showsCurrentLocationButton: false,
                showsFloorPicker: false,
                extendsUnderBottomSafeArea: true
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)
            .accessibilityIdentifier("book-navigation-preparing-map")
        }
    }

    /// 출발지 설정 화면과 같은 제목을 유지해 어떤 책을 찾는 중인지 놓치지 않게 한다.
    private var directHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(originPickerTitle)
                .typography(.title1)
                .lineLimit(2)
            if let subtitle = originPickerSubtitle {
                Text(subtitle)
                    .typography(.title1)
                    .foregroundStyle(DS.ColorToken.neutralTertiary)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(DS.ColorToken.neutralPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .background(alignment: .top) {
            LibraryTopBarBackground()
                .ignoresSafeArea(.container, edges: [.top, .horizontal])
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var directStatus: some View {
        VStack(spacing: 10) {
            Text(isPreparingManualOrigin ? "서가까지\n수동안내를 시작합니다" : "서가까지\n길안내를 준비합니다")
                .typography(.body1)
                .multilineTextAlignment(.center)
                .foregroundStyle(DS.ColorToken.neutralPrimary)
            ProgressView()
                .tint(DS.ColorToken.neutralPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("book-navigation-preparing-status")
    }

    private var directFailure: some View {
        VStack(spacing: 20) {
            ContentUnavailableView("길안내를 시작할 수 없어요", systemImage: "location.slash",
                description: Text(routeError ?? ""))
            Button("다시 시도") { retryDirectNavigation() }
                .buttonStyle(.borderedProminent)
                .disabled(isLoadingRoute)
            Button("출발 위치 직접 설정") { presentOriginPicker() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("book-navigation-set-origin")
            Button("돌아가기") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(24)
    }

    private func retryDirectNavigation() {
        if currentStart == nil { mapStore?.send(.currentLocationTapped) }
        let request = BookRoutePreviewRequest(state: destinationStore?.state, start: currentStart)
        if request == routeRequest {
            routeStore.send(.startRequested(request))
        } else {
            previewStart = currentStart
        }
    }

    var body: some View {
        Group {
            if entryMode == .direct {
                directContent
            } else if destination.books.count > 1, let destinationStore {
                BookRouteBooksPreviewView(
                    books: orderedBooks,
                    shelfStore: destinationStore,
                    session: readySession,
                    isLoadingRoute: isLoadingRoute,
                    routeError: hidesRouteErrorWhileResolvingOrigin ? nil : routeError,
                    canStart: readySession != nil && currentStart != nil && !isLoadingRoute && routeError == nil,
                    onBack: { dismiss() },
                    onStart: { _ in
                        routeStore.send(.startRequested(.init(state: destinationStore.state, start: currentStart)))
                    },
                    onRetry: {
                        if currentStart == nil { mapStore?.send(.currentLocationTapped) }
                        let request = BookRoutePreviewRequest(state: destinationStore.state, start: currentStart)
                        if request == routeRequest {
                            routeStore.send(.requestChanged(request))
                        } else {
                            previewStart = currentStart
                        }
                    },
                    onSetOriginManually: { presentOriginPicker() },
                    homeAnnotations: mapStore?.homeAnnotations
                )
            } else {
                previewContent
            }
        }
        .fullScreenCover(item: $navigationFlow.session, onDismiss: {
            if navigationFlow.presentationDismissed() { dismiss() }
        }) { session in
            BookNavigationView(session: session, analyticsIsTest: destination.isTestMode) { _ in
                navigationFlow.navigationEnded()
            }
        }
        .fullScreenCover(isPresented: $isOriginPickerPresented) {
            originPicker
        }
        .overlay {
            if isPermissionAlertPresented {
                LibraryPermissionAlert(
                    title: "필수 권한에 동의해주세요.",
                    message: "위치 권한을 허용해주세요. 위치를 통해 정확한 책의 위치를 안내합니다.",
                    onCancel: {
                        isPermissionAlertPresented = false
                        isPreparingManualOrigin = true
                    },
                    onConfirm: {
                        isPermissionAlertPresented = false
                        openLocationSettings()
                    })
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isPermissionAlertPresented)
        .onChange(of: isPreparingManualOrigin ? mapStore?.map != nil : false) { _, isMapReady in
            // 지도가 준비된 뒤에 출발지 설정 화면을 연다. 그동안은 수동 안내 준비 문구를 보여 준다.
            if isMapReady { presentOriginPicker() }
        }
        .onChange(of: isPreparingManualOrigin) { _, isPreparing in
            if isPreparing, mapStore?.map != nil { presentOriginPicker() }
        }
        .background(Color(uiColor: .systemBackground))
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .overlay(alignment: .topTrailing) {
            if entryMode == .preview, destination.books.count <= 1, let previewSession {
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
        .analyticsScreen(.routePreview)
        .onChange(of: mapStore?.authorization, initial: true) { _, _ in
            resolveStartAuthorization()
        }
        .onChange(of: currentStart, initial: true) { _, position in
            // 처음 위치·층을 받으면 계산한다. 완료·실패 후 위치 수신마다 재계산하지 않는다.
            if previewSession == nil, !isLoadingRoute,
               previewStart == nil || previewStart?.floorOrdinal == nil {
                previewStart = position
            }
        }
        .onChange(of: routeStore.navigationSession) { _, session in
            guard let session else { return }
            guard currentStart != nil else {
                routeStore.send(.startRequested(.failed(IndoorRoutingError.invalidPosition.localizedDescription)))
                return
            }
            navigationFlow.start(session)
            routeStore.send(.navigationStarted)
        }
        .task(id: destinationStore.map { ObjectIdentifier($0) }) { [destinationStore] in
            // Store 교체 시 기존 로딩 task를 취소해 이전 도서의 응답을 분리한다.
            guard let destinationStore else { return }
            await destinationStore.send(.task).finish()
        }
        .task(id: routeRequest) {
            // 소장·지도 로딩이 끝난 시점의 블루닷에서 안내를 시작한다.
            let request = entryMode == .direct
                ? BookRoutePreviewRequest(state: destinationStore?.state, start: currentStart)
                : routeRequest
            routeFloorID = nil

            if entryMode == .direct {
                await routeStore.send(.startRequested(request)).finish()
            } else {
                await routeStore.send(.requestChanged(request)).finish()
            }
        }
        .onDisappear {
            routeStore.send(.disappeared)
            destinationStore?.send(.map(.disappeared))
        }
    }

    /// 위치 권한이 없으면 설정 앱으로 보내거나 출발 위치를 직접 지정하게 하는 알림을 띄운다.
    ///
    /// iOS는 한 번 거부한 뒤에는 시스템 권한 창을 다시 띄우지 않는다. 그래서 권한 요청 대신
    /// 이 앱의 설정 화면으로 보내는 버튼을 둔다.
    private func resolveStartAuthorization() {
        guard let mapStore, manualStart == nil, !isOriginPickerPresented,
              !isPermissionAlertPresented, navigationFlow.session == nil else { return }
        guard !mapStore.authorization.isAuthorized else { return }
        isPermissionAlertPresented = true
    }

    private func presentOriginPicker() {
        isPreparingManualOrigin = false
        isOriginPickerPresented = true
    }

    /// 설정 앱에서 이 앱의 권한 화면을 연다. 위치 접근을 여기서 바꿀 수 있다.
    private func openLocationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    @ViewBuilder
    private var originPicker: some View {
        if let map = mapStore?.map {
            BookRouteOriginPickerView(
                map: map, title: originPickerTitle, subtitle: originPickerSubtitle,
                initialFloorID: originPickerFloorID,
                onCancel: {
                    isOriginPickerPresented = false
                    dismiss()
                },
                onConfirm: { position in
                    manualStart = position
                    isOriginPickerPresented = false
                    // routeRequest가 바뀌어 지정한 출발 위치로 경로를 다시 계산한다.
                    previewStart = position
                })
        } else {
            VStack(spacing: 20) {
                ContentUnavailableView("지도를 불러오지 못했어요", systemImage: "map",
                    description: Text("실내지도를 불러온 뒤에 출발 위치를 지정할 수 있어요."))
                Button("돌아가기") {
                    isOriginPickerPresented = false
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .preferredColorScheme(.dark)
        }
    }

    private var originPickerTitle: String {
        orderedBooks.first.map { BookText.plainText($0.title) } ?? "도서 길안내"
    }

    /// 시안의 "4층 337번 서가"처럼 목적지 서가를 알려 준다. 서가를 아직 모르면 줄을 숨긴다.
    private var originPickerSubtitle: String? {
        guard let book = orderedBooks.first,
              let shelf = destinationStore?.state.shelves(for: book.id).first else { return nil }
        let floorName = mapStore?.map?.floors.first { $0.id == shelf.floorID }?.name
        return [floorName, "\(shelf.realNumber)번 서가"].compactMap { $0 }.joined(separator: " ")
    }

    /// 목적지 서가와 같은 층에서 시작해 사용자가 층을 덜 바꾸게 한다.
    private var originPickerFloorID: UUID? {
        guard let book = orderedBooks.first,
              let shelf = destinationStore?.state.shelves(for: book.id).first else {
            return mapStore?.selectedFloorID
        }
        return shelf.floorID
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
                ProgressView(isLoadingRoute ? "현재 위치에서 목적지까지 경로 계산 중" : "도서·서가 위치 확인 중")
                    .font(.caption)
            }
            if let routeError {
                Text(routeError).font(.caption).foregroundStyle(.red)
                    .accessibilityIdentifier("preview-test-route-error")
                Button("경로 다시 계산") {
                    let request = BookRoutePreviewRequest(state: destinationStore?.state, start: currentStart)
                    if request == routeRequest {
                        routeStore.send(.requestChanged(request))
                    } else {
                        previewStart = currentStart
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isLoadingRoute || currentStart == nil)
            }
            if let previewSession {
                Text("현재 위치 → " + previewSession.stops.map { "\($0.shelf.realNumber)-\($0.shelf.side.rawValue)" }.joined(separator: " → "))
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
                Button("출발") {
                    // 미리보기를 보는 동안 이동했을 수 있으므로 탭 시점의 위치로 다시 계산한다.
                    routeStore.send(.startRequested(.init(state: destinationStore?.state, start: currentStart)))
                }
                    .font(.headline)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.large)
                    .fixedSize()
                    .disabled(readySession == nil || currentStart == nil || isLoadingRoute || routeError != nil)
                    .accessibilityIdentifier("book-route-preview-start")
                    .accessibilityHint("최신 현재 위치에서 경로를 계산하고 길안내를 시작해요")
            }
            .padding(16)
            .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 20))

            Text(previewSession == nil ? "경로 계산 후 시간·단계·거리가 표시돼요."
                 : "시속 5km 기준 예상 시간이에요(10m ≈ 7.2초). 단계는 그룹 전환 횟수 + 1이며, 주황색 원은 전환 노드예요. 모든 방문 순서 중 실제 이동거리가 가장 짧은 경로예요. 출발을 누르면 최신 현재 위치로 다시 계산해요.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if currentStart == nil {
                Label("현재 위치를 확인한 뒤 길안내를 시작할 수 있어요.", systemImage: "location.slash")
                    .font(.caption)
                Button("현재 위치 확인") { mapStore?.send(.currentLocationTapped) }
                    .disabled(mapStore == nil)
                Button("출발 위치 직접 설정") { presentOriginPicker() }
                    .accessibilityIdentifier("preview-set-origin")
            }
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
                Label("출발 · 현재 위치", systemImage: "location.circle.fill")
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
                                let shelves = destinationStore?.state.shelves(for: book.id) ?? []
                                Text(BookText.plainText(book.title))
                                    .font(.subheadline.bold())
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(BookText.plainText(book.author))
                                    .font(.caption).foregroundStyle(.secondary)
                                holdingInformation(for: book)
                                ForEach(shelves) { shelf in
                                    Text("\(shelves.count > 1 ? "후보 서가" : "서가") \(shelf.realNumber)-\(shelf.side.rawValue)")
                                        .font(.caption.bold()).foregroundStyle(.orange)
                                }
                                if let stop = readySession?.stops.first(where: { $0.book.id == book.id }),
                                   stop.candidateShelves.count > 1 {
                                    Text("안내 목적지: \(stop.shelf.realNumber)-\(stop.shelf.side.rawValue) · 도착 후 두 서가를 확인해 주세요")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
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
