import ComposableArchitecture
import SwiftUI

/// 현재 책까지의 지도와, 거리 비율 진행 바·현재 안내·도서 정보를 담은 네이티브 시트.
struct BookNavigationView: View {
    @State private var store: StoreOf<BookNavigationFeature>
    private let onExit: ((BookNavigationFeature.ExitReason) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var presentsSheet = false
    @State private var sheetHeight: CGFloat = 118
    @State private var detent: PresentationDetent = .height(118)

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
                    .padding(.bottom, max(16, sheetHeight - geometry.safeAreaInsets.bottom + 16))
                }
                .sheet(isPresented: Binding(
                    get: { presentsSheet && !store.isArrivalPresented && store.exitReason == nil },
                    set: { presentsSheet = $0 }
                )) {
                    guidanceSheet
                        .alert("안내를 잠시 멈췄어요.", isPresented: pauseBinding(forArrival: false)) {
                            pauseButtons
                        } message: { pauseMessage }
                        .presentationDetents([.height(118), .medium, .large], selection: $detent)
                        .presentationDragIndicator(.visible)
                        .presentationCornerRadius(24)
                        .presentationBackground(Color(uiColor: .secondarySystemBackground))
                        .presentationBackgroundInteraction(.enabled)
                        .presentationContentInteraction(.resizes)
                        .interactiveDismissDisabled()
                        .preferredColorScheme(.dark)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height + $0.safeAreaInsets.bottom } action: { height in
                            guard height > 0, abs(height - sheetHeight) > 1 else { return }
                            sheetHeight = height
                            store.send(.viewportChanged)
                        }
                }
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
                    onFinish: { store.send(.finishFromArrival(stopIndex: index)) },
                    onCancel: { store.send(.cancelTapped) }
                )
                .id(index)
                // 기존 BookNavigationArrivalView는 책등 화면에서 아래로 3초 이상 당기면 열린다. (15) 책찾기 화면 문서)
            }
        }
        .interactiveDismissDisabled()
        .alert("안내를 잠시 멈췄어요.", isPresented: pauseBinding(forArrival: true)) {
            pauseButtons
        } message: { pauseMessage }
        .onChange(of: store.exitReason) { _, reason in
            guard let reason else { return }
            if let onExit { onExit(reason) } else { dismiss() }
        }
        .onChange(of: store.isArrivalPresented) { _, isPresented in
            if !isPresented, store.exitReason == nil { presentsSheet = true }
        }
        .task {
            presentsSheet = true
            await store.send(.task).finish()
        }
        .onChange(of: scenePhase) { _, phase in store.send(.sceneActiveChanged(phase == .active)) }
        .onDisappear { store.send(.disappeared) }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("book-navigation")
    }

    private func pauseBinding(forArrival: Bool) -> Binding<Bool> {
        Binding(get: { store.isCancelConfirmationPresented && store.isArrivalPresented == forArrival },
                set: { if !$0 { store.send(.cancelDismissed) } })
    }

    @ViewBuilder private var pauseButtons: some View {
        Button("돌아가기", role: .cancel) { store.send(.cancelDismissed) }
        if store.hasNextStop {
            Button("다음 책 찾기") { store.send(.nextBookTapped) }
                .disabled(store.progress?.maneuver != .nearDestination)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: store.instructionSymbol).frame(width: 20)
                Text(store.instructionText ?? store.statusMessage ?? "현재 위치를 확인하고 있어요.")
                    .font(.subheadline.weight(.semibold)).lineLimit(2)
                Spacer(minLength: 0)
                Button { store.send(.arrivalTestTapped) } label: {
                    Image(systemName: "checkmark.circle").font(.title3)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("도착 확인")
                .accessibilityIdentifier("book-navigation-arrival-trigger")
            }
            .accessibilityIdentifier("book-navigation-instruction")
            BookNavigationProgressBar(timeline: store.timeline, stopIndex: store.currentStopIndex, progress: store.progress)
            if detent != .height(118), let info = store.currentBookInfo {
                ScrollView {
                    HStack(alignment: .top, spacing: 18) {
                        BookCoverView(url: info.book.imageURL, isbn: info.book.isbn)
                            .frame(width: 96, height: 144).clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 10) {
                            Text("현재 책").font(.caption.bold()).foregroundStyle(BookNavigationPalette.accent)
                            BookNavigationBookInformationView(info: info)
                            Text(store.remainingMeters.map { "약 \($0.formatted(.number.precision(.fractionLength(0))))m 남음" } ?? "현재 위치 확인 중")
                                .font(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier("book-navigation-remaining-metrics")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
                .id(store.currentStopIndex)
                .accessibilityIdentifier("book-navigation-current-book")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.top, 24)
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
