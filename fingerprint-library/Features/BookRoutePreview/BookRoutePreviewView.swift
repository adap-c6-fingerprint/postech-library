import ComposableArchitecture
import SwiftUI
import UIKit

struct BookRoutePreviewView: View {
    @Bindable var store: StoreOf<BookRoutePreviewFeature>

    private var routeStore: StoreOf<BookRoutePreviewFeature> { store }
    private var entryMode: BookRoutePreviewFeature.EntryMode { store.entryMode }
    private var destination: BookRoutePreviewDestination { store.destination }
    private var destinationStore: StoreOf<BookShelfMapFeature>? {
        store.scope(state: \.shelf, action: \.shelf)
    }

    @State private var routeFloorID: UUID?
    @Environment(\.indoorRouteMapStore) private var mapStore
    @Environment(\.openURL) private var openURL
    @State private var isProblemReportPresented = false
    @State private var isProblemReportFallbackPresented = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var previewPlan: RoutePlan? {
        routeStore.previewPlan
    }
    
    private var isLoadingRoute: Bool {
        routeStore.isLoadingRoute
    }

    private var routeError: String? {
        routeStore.routeError
    }
    
    private let accent = PobookUI.ColorToken.accent
    private var currentStart: IndoorPosition? { store.currentStart }
    private var needsStartLocationSetup: Bool { store.needsStartLocationSetup }
    private var routeRequest: BookRoutePreviewRequest { store.routeRequest }
    private var readySession: RoutePlan? { store.readySession }
    private var orderedBooks: [Book] { store.orderedBooks }

    private var previewContent: some View {
        BookRoutePreviewMapSheet(onBack: { dismiss() }, onViewportChange: {
            if previewPlan == nil { destinationStore?.send(.focusShelfTapped) }
        }) { insets, cameraRevision in
            Group {
                if let previewPlan,
                   let floor = previewPlan.map.floors.first(where: { floor in
                       routeFloorID.map { $0 == floor.id }
                           ?? (floor.ordinal == previewPlan.start.floorOrdinal)
                   }) {
                    IndoorMapKitView(
                        map: previewPlan.map, floor: floor, selectedFeatureID: nil,
                        position: previewPlan.start, showsUserLocation: false, isPlacingOrigin: false,
                        cameraRequest: .init(id: cameraRevision * 100 + floor.ordinal, target: .route(previewPlan.route,
                            featureIDs: previewPlan.stops.flatMap { $0.candidateShelves.map(\.mapElementID) })),
                        onSelect: { _ in }, onPlaceOrigin: { _ in },
                        route: previewPlan.route,
                        groupTransitionNodes: previewPlan.guidance.groupTransitionNodes,
                        viewportInsets: insets,
                        shelfLabels: previewPlan.shelfLabels,
                        highlightedFeatureIDs: Set(previewPlan.stops.flatMap { $0.candidateShelves.map(\.mapElementID) })
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
                    routeFloorID = nil
                    store.send(.testModeTapped)
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

    private var directContent: some View {
        ZStack {
            if showsRouteFailure {
                directFailure
            } else {
                directMapBackdrop
                directHeader
                directStatus
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("book-navigation-preparing")
    }

    private var hidesRouteErrorWhileResolvingOrigin: Bool { store.hidesRouteErrorWhileResolvingOrigin }
    private var showsRouteFailure: Bool { store.showsRouteFailure }

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

    private var directHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(originPickerTitle)
                .typography(.title1)
                .lineLimit(2)
            if let subtitle = originPickerSubtitle {
                Text(subtitle)
                    .typography(.title1)
                    .foregroundStyle(PobookUI.ColorToken.neutralTertiary)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
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
            Text(store.isPreparingManualOrigin ? "서가까지\n수동안내를 시작합니다" : "서가까지\n길안내를 준비합니다")
                .typography(.body1)
                .multilineTextAlignment(.center)
                .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
            ProgressView()
                .tint(PobookUI.ColorToken.neutralPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("book-navigation-preparing-status")
    }

    private var directFailure: some View {
        BookRouteFailureView(
            kind: .init(message: routeError),
            diagnostic: failureDiagnostic,
            isRetrying: isLoadingRoute,
            onBack: { dismiss() },
            onRetry: { retryDirectNavigation() },
            onGoHome: { returnHome() },
            onAddToCart: destination.books.isEmpty ? nil : { addBooksToCart() },
            onReportProblem: { presentProblemReport() })
    }

    private var failureDiagnostic: String {
        let code = IndoorRoutingError.allCases.first { $0.errorDescription == routeError }
            .map { "\($0)" } ?? "unknown"
        var parts = ["E: \(code)"]
        let now = Date()
        if !store.isAuthorized, store.manualStart == nil {
            parts.append("auth \(store.location.authorization)")
        }
        if let position = store.manualStart ?? store.homeManualStart ?? store.location.position {
            parts.append(position.horizontalAccuracy.map { "±\(Int($0.rounded()))m" } ?? "±?m")
            parts.append(position.floorOrdinal.map { "floor \($0)" } ?? "floor nil")
            parts.append("\(Int(now.timeIntervalSince(position.timestamp)))s ago")
            if position.source != .sensor { parts.append("\(position.source)") }
        } else {
            parts.append("no position")
        }
        if let previewStart = store.previewStart {
            parts.append("start \(Int(now.timeIntervalSince(previewStart.timestamp)))s ago")
        }
        return parts.joined(separator: " · ")
    }

    private func returnHome() {
        store.send(.goHomeTapped)
    }

    private func addBooksToCart() {
        store.send(.addToCartTapped)
    }

    private func presentProblemReport() {
        guard !ProblemReportMailSheet.canSendMail else {
            isProblemReportPresented = true
            return
        }
        guard let url = ProblemReportMailSheet.mailtoURL(
            subject: problemReportSubject, body: problemReportBody) else {
            isProblemReportFallbackPresented = true
            return
        }
        openURL(url) { accepted in
            if !accepted { isProblemReportFallbackPresented = true }
        }
    }

    private var problemReportSubject: String { "[포북] 길안내 문제 신고" }

    private var problemReportBody: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        let book = orderedBooks.first.map { BookText.plainText($0.title) } ?? "-"
        return """
        겪으신 상황을 아래에 적어 주세요.


        ---
        증상: \(routeError ?? "길안내를 준비하지 못함")
        책: \(book)
        앱 버전: \(version) (\(build))
        """
    }

    private func retryDirectNavigation() {
        store.send(.directRetryTapped)
    }

    var body: some View {
        Group {
            if entryMode == .direct {
                directContent
            } else if destination.books.count > 1, let destinationStore {
                BookRouteBooksPreviewView(
                    books: orderedBooks,
                    shelfStore: destinationStore,
                    routePlan: readySession,
                    isLoadingRoute: isLoadingRoute,
                    routeError: hidesRouteErrorWhileResolvingOrigin ? nil : routeError,
                    canStart: !isLoadingRoute && (needsStartLocationSetup
                        || (readySession != nil && currentStart != nil && routeError == nil)),
                    onBack: { dismiss() },
                    onStart: { _ in store.send(.startTapped) },
                    onRetry: { store.send(.retryTapped) },
                    onSetOriginManually: { store.send(.setOriginManuallyTapped) },
                    homeAnnotations: mapStore?.homeAnnotations
                )
            } else {
                previewContent
            }
        }
        .fullScreenCover(item: $store.scope(state: \.navigation, action: \.navigation), onDismiss: {
            store.send(.navigationCoverDismissed)
        }) { navigationStore in
            BookNavigationView(store: navigationStore, onExit: { _ in })
        }
        .sheet(isPresented: $isProblemReportFallbackPresented) {
            ProblemReportFallbackSheet(messageBody: problemReportBody) {
                isProblemReportFallbackPresented = false
            }
        }
        .sheet(isPresented: $isProblemReportPresented) {
            ProblemReportMailSheet(subject: problemReportSubject, body: problemReportBody) {
                isProblemReportPresented = false
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: Binding(
            get: { store.isOriginPickerPresented },
            set: { if !$0 { store.send(.originPickerDismissed) } }
        ), onDismiss: {
            store.send(.originPickerDismissed)
        }) {
            originPicker
        }
        .overlay {
            if store.isPermissionAlertPresented {
                LibraryPermissionAlert(
                    title: "필수 권한에 동의해주세요.",
                    message: "위치 권한을 허용해주세요. 위치를 통해 정확한 책의 위치를 안내합니다.",
                    onCancel: { store.send(.permissionAlertCancelTapped) },
                    onConfirm: { store.send(.permissionAlertSettingsTapped) })
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.isPermissionAlertPresented)
        .onChange(of: routeMap != nil, initial: true) { _, isReady in
            store.send(.routeMapAvailabilityChanged(isReady))
        }
        .background(Color(uiColor: .systemBackground))
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .overlay(alignment: .topTrailing) {
            if entryMode == .preview, destination.books.count <= 1, let previewPlan {
                Menu("층 보기", systemImage: "square.3.layers.3d") {
                    ForEach(previewPlan.map.floors) { floor in
                        Button("\(floor.ordinal + 1)층") { routeFloorID = floor.id }
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(16)
            }
        }
        .accessibilityIdentifier("book-route-preview")
        .analyticsScreen(.routePreview)
        .task { store.send(.task) }
        .onChange(of: store.routeRequest) { _, _ in
            routeFloorID = nil
        }
        .task(id: destination) {
            guard store.shelf != nil else { return }
            await store.send(.shelf(.task)).finish()
        }
        .onDisappear {
            routeStore.send(.disappeared)
            if store.shelf != nil { store.send(.shelf(.map(.disappeared))) }
        }
    }

    private var routeMap: IndoorMap? {
        mapStore?.map ?? destinationStore?.state.map.map
    }

    @ViewBuilder
    private var originPicker: some View {
        if let map = routeMap {
            BookRouteOriginPickerView(
                map: map, title: originPickerTitle, subtitle: originPickerSubtitle,
                initialFloorID: originPickerFloorID,
                onCancel: { store.send(.originPickerCancelled) },
                onConfirm: { position in store.send(.originConfirmed(position)) })
        } else {
            VStack(spacing: 20) {
                ContentUnavailableView("지도를 불러오지 못했어요", systemImage: "map",
                    description: Text("실내지도를 불러온 뒤에 출발 위치를 지정할 수 있어요."))
                Button("돌아가기") { store.send(.originPickerCancelled) }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .preferredColorScheme(.dark)
        }
    }

    private var originPickerTitle: String {
        orderedBooks.first.map { BookText.plainText($0.title) } ?? "도서 길안내"
    }

    private var originPickerSubtitle: String? {
        guard let book = orderedBooks.first,
              let shelf = destinationStore?.state.shelves(for: book.id).first else { return nil }
        let floorName = routeMap?.floors.first { $0.id == shelf.floorID }?.name
        return [floorName, shelf.shelfTitle].compactMap { $0 }.joined(separator: " ")
    }

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
            if destinationStore != nil, previewPlan == nil, routeError == nil {
                ProgressView(isLoadingRoute ? "현재 위치에서 목적지까지 경로 계산 중" : "도서·서가 위치 확인 중")
                    .font(.caption)
            }
            if let routeError {
                Text(routeError).font(.caption).foregroundStyle(.red)
                    .accessibilityIdentifier("preview-test-route-error")
                Button("경로 다시 계산") { store.send(.retryTapped) }
                .buttonStyle(.bordered)
                .disabled(isLoadingRoute || currentStart == nil)
            }
            if let previewPlan {
                Text("현재 위치 → " + previewPlan.stops.map { $0.shelf.faceTitle }.joined(separator: " → "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            layout {
                HStack(spacing: 12) {
                    metric("도보", unit: "min", value: previewPlan.map {
                        $0.guidance.walkingMinutes.formatted(.number.precision(.fractionLength(2)))
                    })
                    metric("단계", unit: "steps", value: previewPlan.map { String($0.guidance.stepCount) })
                    metric("거리", unit: "m", value: previewPlan.map { $0.route.distanceMeters.formatted(.number.precision(.fractionLength(0))) })
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("출발") { store.send(.departTapped) }
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

            Text(previewPlan == nil ? "경로 계산 후 시간·단계·거리가 표시돼요."
                 : "시속 5km 기준 예상 시간이에요(10m ≈ 7.2초). 단계는 그룹 전환 횟수 + 1이며, 주황색 원은 전환 노드예요. 모든 방문 순서 중 실제 이동거리가 가장 짧은 경로예요. 출발을 누르면 최신 현재 위치로 다시 계산해요.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if currentStart == nil {
                Label("현재 위치를 확인한 뒤 길안내를 시작할 수 있어요.", systemImage: "location.slash")
                    .font(.caption)
                Button("현재 위치 확인") { mapStore?.send(.currentLocationTapped) }
                    .disabled(mapStore == nil)
                Button("출발 위치 직접 설정") { store.send(.setOriginManuallyTapped) }
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
                                    Text("\(shelves.count > 1 ? "후보 서가" : "서가") \(shelf.faceTitle)")
                                        .font(.caption.bold()).foregroundStyle(.orange)
                                }
                                if let stop = readySession?.stops.first(where: { $0.book.id == book.id }),
                                   stop.candidateShelves.count > 1 {
                                    Text("안내 목적지: \(stop.shelf.faceTitle) · 도착 후 두 서가를 확인해 주세요")
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
        BookRoutePreviewView(store: Store(initialState: BookRoutePreviewFeature.State()) {
            BookRoutePreviewFeature()
        })
    }
}
