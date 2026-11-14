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

    @Environment(\.indoorRouteMapStore) private var mapStore
    @Environment(\.openURL) private var openURL
    @State private var isProblemReportPresented = false
    @State private var isProblemReportFallbackPresented = false
    @Environment(\.dismiss) private var dismiss

    private var isLoadingRoute: Bool {
        routeStore.isLoadingRoute
    }

    private var routeError: RouteFailure? {
        routeStore.routeError
    }
    
    private var currentStart: IndoorPosition? { store.currentStart }
    private var needsStartLocationSetup: Bool { store.needsStartLocationSetup }
    private var readySession: RoutePlan? { store.readySession }
    private var orderedBooks: [Book] { store.orderedBooks }

    private var directContent: some View {
        ZStack {
            if showsRouteFailure {
                directFailure
            } else if hidesRouteErrorWhileResolvingOrigin {
                directLoadingBackdrop
                directHeader
                directStatus
            } else {
                BookRoutePreparingView(onBack: { dismiss() }, onGoHome: { returnHome() })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .accessibilityIdentifier("book-navigation-preparing")
    }

    private var hidesRouteErrorWhileResolvingOrigin: Bool { store.hidesRouteErrorWhileResolvingOrigin }
    private var showsRouteFailure: Bool { store.showsRouteFailure }

    private var directLoadingBackdrop: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            directMapBackdrop
            Rectangle()
                .fill(.regularMaterial)
                .overlay(Color.black.opacity(0.25))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .accessibilityIdentifier("book-navigation-preparing-background")
    }

    @ViewBuilder
    private var directMapBackdrop: some View {
        if let destinationStore {
            GeometryReader { geometry in
                let shelves = destinationStore.shelves
                let floor = shelves.first.flatMap { shelf in
                    destinationStore.map.map?.floors.first { $0.id == shelf.floorID }
                }
                BookDetailShelfMapView(
                    store: destinationStore.scope(state: \.map, action: \.map),
                    floor: floor, shelves: shelves.filter { $0.floorID == floor?.id },
                    mapSize: geometry.size, bottomContentInset: 0,
                    isReadyToFocus: true, homeAnnotations: mapStore?.homeAnnotations,
                    hiddenFavoriteMarkerIDs: Set([destinationStore.sourceFavoriteMarkerID].compactMap { $0 })
                )
            }
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
            if let notice = store.startNotice {
                RouteStartNoticeView(notice: notice)
                    .typography(.caption1)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("출발 위치 직접 설정") { store.send(.setOriginManuallyTapped) }
                    .font(.caption.bold())
                    .accessibilityIdentifier("book-navigation-preparing-set-origin")
            }
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("book-navigation-preparing-status")
    }

    private var directFailure: some View {
        BookRouteFailureView(
            kind: .init(failure: store.failureMessage),
            diagnostic: failureDiagnostic,
            isRetrying: store.isRetryingDirectNavigation,
            onBack: { dismiss() },
            onRetry: { retryDirectNavigation() },
            onGoHome: { returnHome() },
            onAddToCart: destination.books.isEmpty ? nil : { addBooksToCart() },
            onReportProblem: { presentProblemReport() })
    }

    private var failureDiagnostic: String {
        let code = store.failureMessage?.diagnosticCode ?? "unknown"
        var parts = ["E: \(code)"]
        let now = Date()
        if !store.isAuthorized, store.manualStart == nil {
            parts.append("auth \(store.location.authorization)")
        }
        if let position = store.manualStart ?? store.location.position {
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
        증상: \(routeError?.message ?? "길안내를 준비하지 못함")
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
            } else if let destinationStore {
                BookRouteBooksPreviewView(
                    books: orderedBooks,
                    shelfStore: destinationStore,
                    routePlan: readySession,
                    isLoadingRoute: isLoadingRoute,
                    routeError: hidesRouteErrorWhileResolvingOrigin ? nil : routeError?.message,
                    startNotice: store.startNotice,
                    canStart: !isLoadingRoute && (needsStartLocationSetup
                        || (readySession != nil && currentStart != nil && routeError == nil)),
                    onBack: { dismiss() },
                    onStart: { _ in store.send(.startTapped) },
                    onRetry: { store.send(.retryTapped) },
                    onSetOriginManually: { store.send(.setOriginManuallyTapped) },
                    homeAnnotations: mapStore?.homeAnnotations
                )
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
        .accessibilityIdentifier("book-route-preview")
        .analyticsScreen(.routePreview)
        .task { store.send(.task) }
        .task(id: destination) {
            guard store.shelf != nil else { return }
            await store.send(.shelf(.prepareMap)).finish()
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
                startNotice: store.startNotice,
                initialFloorID: originPickerFloorID,
                onCancel: { store.send(.originPickerCancelled) },
                onConfirm: { coordinate, floorOrdinal in
                    store.send(.originConfirmed(coordinate, floorOrdinal: floorOrdinal))
                })
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
}
