import ComposableArchitecture
import SwiftUI

/// 현재 책까지의 지도와, 화면 폭을 채우는 길안내 시트.
struct BookNavigationView: View {
    @State private var store: StoreOf<BookNavigationFeature>
    private let onExit: ((BookNavigationFeature.ExitReason) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheetHeight: CGFloat = 113
    @State private var sheetSummaryHeight: CGFloat = 89
    @ScaledMetric(relativeTo: .body) private var expandedSheetHeight: CGFloat = 352
    private var isSheetExpanded: Bool { store.isSheetExpanded }

    init(session: BookNavigationSession, onExit: ((BookNavigationFeature.ExitReason) -> Void)? = nil) {
        self.init(store: Store(initialState: BookNavigationFeature.State(session: session)) {
            BookNavigationFeature()
        }, onExit: onExit)
    }

    init(store: StoreOf<BookNavigationFeature>, onExit: ((BookNavigationFeature.ExitReason) -> Void)? = nil) {
        self.onExit = onExit
        _store = State(initialValue: store)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    if let stop = store.currentStop, let route = store.currentRoute, let floor = store.currentFloor {
                        navigationMap(stop: stop, route: route, floor: floor)
                            .ignoresSafeArea(.container, edges: [.top, .bottom])
                    } else {
                        ContentUnavailableView("안내 정보를 확인해 주세요", systemImage: "map")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 250).ignoresSafeArea(.container, edges: .top)
                        .allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        if store.canConfirmCurrentFloor { currentFloorMenu }
                    }
                    .padding(.horizontal, 20).padding(.top, 20)
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button { store.send(.recenterTapped) } label: {
                                Image(systemName: "scope").font(.title3)
                                    .frame(width: 48, height: 48).glassEffect(.regular, in: .circle)
                            }
                            .accessibilityLabel("현재 위치로 지도 이동")
                            .accessibilityIdentifier("book-navigation-recenter")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, sheetHeight + 16)
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
                    session: store.session, currentStopIndex: index,
                    bookInformation: store.currentBookInfo,
                    spine: store.arrivalSpines[index],
                    onTask: { store.send(.arrivalSpineTask(stopIndex: index)) },
                    onContinue: { store.send(.continueFromArrival(stopIndex: index)) },
                    onFinish: { store.send(.finishFromArrival(stopIndex: index)) }
                )
                .id(index)
                // 기존 BookNavigationArrivalView는 삭제하지 않고 남겨 둔다. (15) 책찾기 화면 문서)
            }
        }
        .interactiveDismissDisabled()
        .alert("안내를 잠시 멈췄어요.", isPresented: pauseBinding) {
            pauseButtons
        } message: { pauseMessage }
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
    }

    private var pauseBinding: Binding<Bool> {
        Binding(get: { store.isCancelConfirmationPresented },
                set: { if !$0 { store.send(.cancelDismissed) } })
    }

    @ViewBuilder private var pauseButtons: some View {
        Button("돌아가기", role: .cancel) { store.send(.cancelDismissed) }
        if store.hasNextStop {
            Button("다음 책 찾기") { store.send(.nextBookTapped) }
                .disabled(store.isReroutingToNextBook)
        }
        Button("안내 종료하기", role: .destructive) { store.send(.cancelConfirmed) }
    }

    private var pauseMessage: Text {
        Text("안내로 돌아가서 책을 다시 찾거나 안내를 종료할 수 있어요.")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.currentBookInfo.map { BookText.plainText($0.book.title) } ?? "도서 길안내")
                    .font(.title3.bold()).lineLimit(2)
                    .accessibilityIdentifier("book-navigation-book-title")
                if let info = store.currentBookInfo {
                    Text("\(info.floorName ?? "") \(info.shelf.realNumber)번 서가")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                        .accessibilityIdentifier("book-navigation-shelf")
                }
            }
            Spacer(minLength: 0)
            Button { store.send(.cancelTapped) } label: {
                Image(systemName: "pause.fill").frame(width: 44, height: 44)
                    .glassEffect(.regular, in: .circle)
            }
            .accessibilityLabel("안내 일시 정지")
            .accessibilityIdentifier("book-navigation-cancel")
        }
        .foregroundStyle(.white)
    }

    private var guidanceSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: store.instructionSymbol)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .background(.black, in: Circle())
                        Text(store.nextBookRouteError ?? store.instructionText ?? store.statusMessage ?? "현재 위치를 확인하고 있어요.")
                            .font(.body.weight(.medium)).lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 28)
                    .accessibilityIdentifier("book-navigation-instruction")
                    BookNavigationProgressBar(timeline: store.timeline, stopIndex: store.currentStopIndex,
                        progress: store.progress, floors: store.session.map.floors)
                }
                .padding(.horizontal, 16)
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                    .padding(.horizontal, 14).padding(.top, 20)
                    .accessibilityHidden(true)
            }
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                // 접힌 높이는 디바이더 위치로 정한다. 안내가 두 줄이 되어도 잘리지 않는다.
                if abs(height - sheetSummaryHeight) > 0.5 { sheetSummaryHeight = height }
            }
            if isSheetExpanded, let info = store.currentBookInfo, let route = store.currentRoute {
                BookNavigationCurrentBookCard(info: info, route: route)
                    .padding(.horizontal, 16).padding(.top, 24)
                    .id(store.currentStopIndex)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tint(BookNavigationPalette.accent)
    }

    private var currentFloorMenu: some View {
        Menu {
            ForEach(store.session.map.floors) { floor in
                Button(floor.name) { store.send(.currentFloorConfirmed(floor.ordinal)) }
            }
        } label: {
            Label(store.effectiveFloorOrdinal.flatMap { ordinal in store.session.map.floors.first { $0.ordinal == ordinal }?.name }
                  ?? "현재 층 선택", systemImage: "square.3.layers.3d")
                .font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6)
                .background(.black.opacity(0.5), in: Capsule())
        }
        .accessibilityLabel("현재 층 확인")
        .accessibilityIdentifier("book-navigation-current-floor")
    }

    private func navigationMap(stop: BookNavigationStop, route: IndoorRoute, floor: IndoorMapFloor) -> some View {
        IndoorMapKitView(
            map: store.session.map, floor: floor, selectedFeatureID: nil,
            position: store.latestPosition, showsUserLocation: false, isPlacingOrigin: false,
            cameraRequest: store.cameraRequest, onSelect: { _ in }, onPlaceOrigin: { _ in },
            route: route, viewportInsets: .init(top: 140, left: 0, bottom: sheetHeight, right: 0),
            shelfLabels: stop.candidateShelves, highlightedFeatureIDs: Set(stop.candidateShelves.map(\.mapElementID)),
            navigationAppearance: true, navigationBearingRadians: store.navigationBearing,
            navigationDestination: store.currentPlan.map { .init(book: stop.book, coordinate: $0.destination.coordinate, floorID: stop.shelf.floorID) },
            onUserCameraInteraction: { store.send(.mapInteractionBegan) }
        )
        .accessibilityIdentifier("book-navigation-map")
    }
}
