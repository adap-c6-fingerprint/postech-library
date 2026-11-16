import ComposableArchitecture
import SwiftUI

struct BookNavigationView: View {
    @Bindable private var store: StoreOf<BookNavigationFeature>
    private let onExit: ((BookNavigationFeature.ExitReason) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheetHeight: CGFloat = 92
    @State private var sheetSummaryHeight: CGFloat = 68
    @ScaledMetric(relativeTo: .body) private var expandedSheetHeight: CGFloat = 352
    private var isSheetExpanded: Bool { store.isSheetExpanded }

    init(store: StoreOf<BookNavigationFeature>, onExit: ((BookNavigationFeature.ExitReason) -> Void)? = nil) {
        self.onExit = onExit
        self.store = store
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    if let stop = store.currentStop, let route = store.currentRoute, let floor = store.currentFloor {
                        navigationMap(stop: stop, route: route, floor: floor)
                            .overlay {
                                if store.diagnostics.isPlacingCheckpoint { BookNavigationDiagnosticsCrosshair() }
                            }
                            .ignoresSafeArea(.container, edges: [.top, .bottom])
                    } else {
                        ContentUnavailableView("안내 정보를 확인해 주세요", systemImage: "map")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    VStack(spacing: 0) {
                        LibraryTopBarBackground()
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .ignoresSafeArea(.container, edges: [.top, .horizontal])
                    .allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: 38) {
                        header
                        VStack(alignment: .leading, spacing: 12) {
                            currentFloorIndicator
                            if store.diagnostics.isRecording { BookNavigationDiagnosticsHUD(store: store) }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 20)
                    VStack(spacing: PobookUI.Spacing._16) {
                        Spacer()
                        // 지도 중앙 십자선을 가리지 않도록 기준점 안내는 아래쪽에 둔다.
                        if store.diagnostics.isPlacingCheckpoint { BookNavigationCheckpointBar(store: store) }
                        HStack {
                            Spacer(minLength: 0)
                            MapRecenterButton(accessibilityIdentifier: "book-navigation-recenter") {
                                store.send(.recenterTapped)
                            }
                        }
                        HStack(alignment: .bottom, spacing: PobookUI.Spacing._8) {
                            if store.currentStopIndex == 0 {
                                Spacer(minLength: 0)
                            } else {
                                if store.canReturnToPreviousStop { previousShelfButton }
                                Spacer(minLength: 0)
                            }
                            if let transition = store.nextFloorTransition {
                                floorTransitionButton(transition, stopIndex: store.currentStopIndex)
                            } else if store.canMarkShelfFound {
                                shelfFoundButton
                            }
                            if store.currentStopIndex == 0 { Spacer(minLength: 0) }
                        }
                    }
                    .padding(.horizontal, PobookUI.Spacing._16)
                    .padding(.bottom, sheetHeight + PobookUI.Spacing._16)
                }
                .overlay(alignment: .bottom) {
                    if !store.isArrivalPresented, store.exitReason == nil {
                        BookNavigationBottomSheet(
                            isExpanded: Binding(get: { store.isSheetExpanded },
                                set: { store.send(.sheetExpansionChanged($0)) }),
                            height: min(isSheetExpanded ? expandedSheetHeight : 24 + sheetSummaryHeight + geometry.safeAreaInsets.bottom,
                                max(24 + sheetSummaryHeight + geometry.safeAreaInsets.bottom,
                                    geometry.size.height + geometry.safeAreaInsets.bottom - 140)),
                            bottomInset: geometry.safeAreaInsets.bottom
                        ) {
                            guidanceSheet
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            guard height > 0, abs(height - sheetHeight) > 1 else { return }
                            sheetHeight = height
                            store.send(.viewportChanged)
                        }
                    }
                }
                .ignoresSafeArea(.container, edges: .bottom)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: Binding(
                get: { store.isArrivalPresented },
                set: { store.send(.arrivalPresentationChanged($0)) }
            )) {
                let index = store.currentStopIndex
                BookNavigationBookFindingView(
                    routePlan: store.routePlan, currentStopIndex: index,
                    bookInformation: store.currentBookInfo,
                    spine: store.arrivalSpines[index],
                    onTask: { store.send(.arrivalSpineTask(stopIndex: index)) },
                    onContinue: { store.send(.continueFromArrival(stopIndex: index)) },
                    onFinish: { store.send(.finishFromArrival(stopIndex: index)) },
                    onDefer: { store.send(.deferFromArrival(stopIndex: index)) },
                    onCancel: { store.send(.cancelTapped) },
                    onAnalyticsButton: { id, screen in store.send(.spineButtonTapped(id, screen: screen)) }
                )
                .id(index)
            }
        }
        .interactiveDismissDisabled()
        .sheet(isPresented: Binding(get: { store.diagnostics.isPanelPresented },
                                    set: { store.send(.diagnostics(.panelPresentationChanged($0))) })) {
            BookNavigationDiagnosticsPanel(store: store)
                .presentationDetents([.medium, .large])
        }
        .overlay {
            if store.isCancelConfirmationPresented {
                BookNavigationPauseAlert(
                    hasNextStop: store.hasNextStop,
                    isReroutingToNextBook: store.isReroutingToNextBook,
                    onResume: { store.send(.cancelDismissed) },
                    onNextBook: { store.send(.nextBookTapped) },
                    onEnd: { store.send(.cancelConfirmed) }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.isCancelConfirmationPresented)
        .allowsHitTesting(!store.isNextBookOriginPickerPresented)
        .accessibilityHidden(store.isNextBookOriginPickerPresented)
        .overlay {
            if store.isNextBookOriginPickerPresented {
                nextBookOriginPicker
                    .accessibilityAddTraits(.isModal)
            }
        }
        .onChange(of: store.exitReason) { _, reason in
            guard let reason else { return }
            if let onExit { onExit(reason) } else { dismiss() }
        }
        .task {
            await store.send(.task).finish()
        }
        .onChange(of: scenePhase) { _, phase in store.send(.sceneActiveChanged(phase == .active)) }
        .onDisappear { store.send(.disappeared) }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("book-navigation")
        .analyticsScreen(.navigation)
    }

    @ViewBuilder
    private var nextBookOriginPicker: some View {
        let nextIndex = store.currentStopIndex + 1
        if store.routePlan.stops.indices.contains(nextIndex) {
            let stop = store.routePlan.stops[nextIndex]
            let floorName = store.routePlan.map.floors.first { $0.id == stop.shelf.floorID }
                .map { "\($0.ordinal + 1)층" }
            BookRouteOriginPickerView(
                map: store.routePlan.map,
                title: BookText.plainText(stop.book.title),
                subtitle: [floorName, stop.shelf.shelfTitle].compactMap { $0 }.joined(separator: " "),
                initialFloorID: store.currentFloor?.id ?? stop.shelf.floorID,
                onCancel: { store.send(.nextBookOriginPickerDismissed) },
                onConfirm: { coordinate, floorOrdinal in
                    store.send(.nextBookOriginConfirmed(coordinate, floorOrdinal: floorOrdinal))
                })
        }
    }

    #if DEBUG
    private static let isDiagnosticsMenuAvailable = true
    #else
    private static let isDiagnosticsMenuAvailable = false
    #endif

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.currentBookInfo.map { BookText.plainText($0.book.title) } ?? "도서 길안내")
                    .typography(.title1)
                    .lineLimit(2)
                    .accessibilityIdentifier("book-navigation-book-title")
                if let info = store.currentBookInfo {
                    Text("\(info.floorName ?? "") \(info.shelf.shelfTitle)")
                        .typography(.title1)
                        .foregroundStyle(PobookUI.ColorToken.neutralTertiary)
                        .accessibilityIdentifier("book-navigation-shelf")
                }
            }
            Spacer(minLength: 0)
            // 진단 메뉴는 Debug 빌드 또는 검색창 /test 측정 모드에서만 보인다.
            if Self.isDiagnosticsMenuAvailable || store.diagnostics.isAutoMode {
                Button { store.send(.diagnostics(.panelButtonTapped)) } label: {
                    Image(systemName: store.diagnostics.isRecording ? "record.circle" : "waveform.path.ecg")
                        .foregroundStyle(store.diagnostics.isRecording ? .red : .white)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular, in: .circle)
                }
                .accessibilityLabel(store.diagnostics.isRecording ? "위치 진단 기록 중, 진단 메뉴 열기" : "위치 진단")
                .accessibilityIdentifier("book-navigation-diagnostics")
            }
            Button { store.send(.cancelTapped) } label: {
                Image(systemName: "xmark").frame(width: 44, height: 44)
                    .glassEffect(.regular, in: .circle)
            }
            .accessibilityLabel("안내 종료")
            .accessibilityIdentifier("book-navigation-cancel")
        }
        .foregroundStyle(.white)
    }

    private var previousShelfButton: some View {
        Button { store.send(.previousStopTapped) } label: {
            Label("이전 서가", systemImage: "chevron.backward")
                .typography(.body2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, PobookUI.Spacing._16)
                .padding(.vertical, PobookUI.Spacing._10)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: PobookUI.Radius.mapActionButton))
        }
        .buttonStyle(.plain)
        .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
        .accessibilityHint("이전 책의 서가로 다시 안내해요")
        .accessibilityIdentifier("book-navigation-previous-shelf")
    }

    private var shelfFoundButton: some View {
        Button { store.send(.shelfFoundTapped) } label: {
            Text("\(store.currentStop?.shelf.shelfTitle ?? "서가") 도착 시 눌러주세요")
                .typography(.body2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, PobookUI.Spacing._16)
                .padding(.vertical, PobookUI.Spacing._10)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: PobookUI.Radius.mapActionButton))
        }
        .buttonStyle(.plain)
        .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
        .accessibilityHint("책장 앞 책등 찾기 화면으로 이동해요")
        .accessibilityIdentifier("book-navigation-shelf-found")
    }

    private var guidanceSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: store.instructionSymbol)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 23, height: 23)
                        .background(.black, in: Circle())
                        .accessibilityHidden(true)
                    Text(store.nextBookRouteError ?? store.statusMessage ?? store.instructionText ?? "현재 위치를 확인하고 있어요.")
                        .typography(.body2).lineLimit(2)
                        .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 28)
                .accessibilityIdentifier("book-navigation-instruction")

                BookNavigationProgressBar(timeline: store.timeline, stopIndex: store.currentStopIndex,
                    progress: store.displayedProgress, floors: store.routePlan.map.floors)
            }
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if abs(height - sheetSummaryHeight) > 0.5 { sheetSummaryHeight = height }
            }
            if isSheetExpanded {
                Rectangle().fill(PobookUI.ColorPrimitive.Grayscale._700).frame(height: 1)
                    .accessibilityHidden(true)
                if let info = store.currentBookInfo, let route = store.currentRoute {
                    BookNavigationCurrentBookCard(info: info, route: route)
                        .id(store.currentStopIndex)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16)
        .tint(BookNavigationPalette.accent)
    }

    @ViewBuilder
    private var currentFloorIndicator: some View {
        if store.canConfirmCurrentFloor {
            currentFloorMenu
        } else if let floor = store.currentFloor {
            IndoorMapFloorBadge(floor: floor, isCurrent: true)
                .accessibilityIdentifier("book-navigation-current-floor")
        }
    }

    private var currentFloorMenu: some View {
        Menu {
            ForEach(store.routePlan.map.floors) { floor in
                Button(floor.name) { store.send(.currentFloorConfirmed(floor.ordinal)) }
            }
        } label: {
            if let floor = store.currentFloor {
                IndoorMapFloorBadge(floor: floor, isCurrent: true)
            } else {
                Label("현재 층 선택", systemImage: "square.3.layers.3d")
                    .font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.black.opacity(0.5), in: Capsule())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.currentFloor.map { "현재 \($0.name), 층 선택" } ?? "현재 층 선택")
        .accessibilityIdentifier("book-navigation-current-floor")
    }

    private func floorTransitionButton(_ transition: BookNavigationFloorTransition, stopIndex: Int) -> some View {
        Button {
            store.send(.floorTransitionTapped(stopIndex: stopIndex, stepIndex: transition.id))
        } label: {
            Text(transition.buttonTitle)
                .typography(.body2)
                .multilineTextAlignment(.center)
                .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, PobookUI.Spacing._16)
                .padding(.vertical, PobookUI.Spacing._10)
                .glassEffect(.regular.tint(.black.opacity(0.2)).interactive(),
                    in: .rect(cornerRadius: PobookUI.Radius.mapActionButton))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("book-navigation-floor-transition")
        .accessibilityHint("\(store.routePlan.map.floors.first { $0.id == transition.to.floorID }?.name ?? "다음 층") 경로를 표시합니다")
    }

    private func navigationMap(stop: RouteStop, route: IndoorRoute, floor: IndoorMapFloor) -> some View {
        BookNavigationMap(store: store, stop: stop, route: route, floor: floor, sheetHeight: sheetHeight)
    }
}

private struct BookNavigationMap: View {
    let store: StoreOf<BookNavigationFeature>
    let stop: RouteStop
    let route: IndoorRoute
    let floor: IndoorMapFloor
    let sheetHeight: CGFloat

    var body: some View {
        IndoorMapKitView(
            map: store.routePlan.map, floor: floor,
            position: store.mapPosition, showsUserLocation: false,
            cameraRequest: store.cameraRequest,
            route: route, entranceApproach: store.entranceApproach, viewportInsets: .init(top: 140, left: 0,
                bottom: sheetHeight + (store.nextFloorTransition == nil ? 0 : 50), right: 0),
            shelfLabels: stop.candidateShelves, highlightedFeatureIDs: Set(stop.candidateShelves.map(\.mapElementID)),
            navigationAppearance: true,
            navigationDestination: store.currentPlan.map { .init(book: stop.book, coordinate: $0.destination.coordinate, floorID: stop.shelf.floorID) },
            onUserCameraInteraction: { store.send(.mapInteractionBegan) },
            onCenterChanged: store.diagnostics.isPlacingCheckpoint
                ? { coordinate, _ in store.send(.diagnostics(.checkpointCenterChanged(coordinate))) } : nil
        )
        .accessibilityIdentifier("book-navigation-map")
    }
    // 기기 방향(deviceHeadingDegrees)을 읽는 곳을 이 뷰로 한정해, 나침반 갱신 때 안내 시트·상단 UI는 다시 계산되지 않게 한다.
}
