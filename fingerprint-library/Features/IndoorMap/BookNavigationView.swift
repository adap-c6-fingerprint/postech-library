import ComposableArchitecture
import SwiftUI

/// 전체 지도 위에 현재 책·예상 이동량·안내 캡슐과 취소/위치 조작을 겹친다.
struct BookNavigationView: View {
    @State private var store: StoreOf<BookNavigationFeature>
    private let onExit: ((BookNavigationFeature.ExitReason) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(session: BookNavigationSession, onExit: ((BookNavigationFeature.ExitReason) -> Void)? = nil) {
        self.onExit = onExit
        _store = State(initialValue: Store(initialState: BookNavigationFeature.State(session: session)) {
            BookNavigationFeature()
        })
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    if let stop = store.currentStop, let route = store.currentRoute, let floor = store.currentFloor {
                        navigationMap(stop: stop, route: route, floor: floor, height: geometry.size.height)
                            .ignoresSafeArea(.container, edges: [.top, .bottom])
                    } else {
                        ContentUnavailableView("안내 정보를 확인해 주세요", systemImage: "map")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    LinearGradient(colors: [.black.opacity(0.95), .black.opacity(0.75), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 330).ignoresSafeArea(.container, edges: .top)
                        .allowsHitTesting(false)
                    VStack(spacing: 24) {
                        header
                        instructionCapsule
                        if store.canConfirmCurrentFloor { currentFloorMenu }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomControls.padding(.horizontal, 28).padding(.bottom, 16) }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: Binding(
                get: { store.isArrivalPresented },
                set: { store.send(.arrivalPresentationChanged($0)) }
            )) {
                let index = store.currentStopIndex
                BookNavigationArrivalView(
                    session: store.session, currentStopIndex: index,
                    bookInformation: store.currentBookInfo,
                    onContinue: { store.send(.continueFromArrival(stopIndex: index)) },
                    onFinish: { store.send(.finishFromArrival(stopIndex: index)) },
                    onCancel: { store.send(.cancelTapped) }
                )
            }
        }
        .interactiveDismissDisabled()
        .alert("안내를 취소할까요?", isPresented: Binding(
            get: { store.isCancelConfirmationPresented },
            set: { if !$0 { store.send(.cancelDismissed) } }
        )) {
            Button("계속 안내", role: .cancel) { store.send(.cancelDismissed) }
            Button("안내 취소", role: .destructive) { store.send(.cancelConfirmed) }
        } message: {
            Text("진행 중인 안내를 종료하고 이전 화면으로 돌아가요.")
        }
        .onChange(of: store.exitReason) { _, reason in
            guard let reason else { return }
            if let onExit { onExit(reason) } else { dismiss() }
        }
        .task { await store.send(.task).finish() }
        .onChange(of: scenePhase) { _, phase in store.send(.sceneActiveChanged(phase == .active)) }
        .onDisappear { store.send(.disappeared) }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("book-navigation")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            if let info = store.currentBookInfo {
                BookNavigationBookInformationView(info: info, compact: true)
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(store.remainingMetrics.map { String($0.minutes) } ?? "—")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("분").font(.subheadline.bold())
                }
                .foregroundStyle(store.isApproachingShelf ? BookNavigationPalette.accent : .white)
                .accessibilityLabel(store.remainingMetrics.map { "예상 \($0.minutes)분" } ?? "예상 시간 확인 전")
                Text(store.remainingMetrics.map { "약 \($0.steps)걸음" } ?? "걸음 수 확인 전")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    .accessibilityHint("걸음 수는 거리로 계산한 예상치예요")
            }
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("book-navigation-remaining-metrics")
        }
    }

    private var instructionCapsule: some View {
        HStack(spacing: 12) {
            Image(systemName: store.isApproachingShelf ? "books.vertical" : store.instructionSymbol)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(store.isApproachingShelf ? BookNavigationPalette.accent : .white)
                .frame(width: 50, height: 50).background(.black, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if store.isApproachingShelf, let stop = store.currentStop {
                    Text("\(stop.shelf.realNumber)번 서가 \(stop.shelf.side.rawValue)면")
                        .font(.callout.weight(.semibold))
                    if case let .callNumberRange(start, end) = stop.shelf.content {
                        Text("\(start) ~ \(end)").font(.callout)
                    } else {
                        Text("서가와 청구기호를 확인해 주세요").font(.callout)
                    }
                } else {
                    Text(store.instructionText ?? store.statusMessage ?? "현재 위치를 확인하고 있어요.")
                        .font(.callout.weight(.medium))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(minHeight: 74)
        .foregroundStyle(.black)
        .background(store.isApproachingShelf ? BookNavigationPalette.accent : .white, in: RoundedRectangle(cornerRadius: 40))
        .accessibilityIdentifier("book-navigation-instruction")
    }

    private var currentFloorMenu: some View {
        Menu {
            ForEach(store.session.map.floors) { floor in
                Button(floor.name) { store.send(.currentFloorConfirmed(floor.ordinal)) }
            }
        } label: {
            Label(store.effectiveFloorOrdinal.flatMap { ordinal in store.session.map.floors.first { $0.ordinal == ordinal }?.name }
                  ?? "현재 층 선택", systemImage: "square.3.layers.3d")
                .font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 9)
                .background(.black.opacity(0.75), in: Capsule())
        }
        .foregroundStyle(.white)
        .accessibilityLabel("현재 층 확인")
        .accessibilityIdentifier("book-navigation-current-floor")
    }

    private var bottomControls: some View {
        HStack {
            Button { store.send(.cancelTapped) } label: { controlIcon("pause.fill") }
                .accessibilityLabel("안내 취소")
                .accessibilityIdentifier("book-navigation-cancel")
            Spacer()
            Button("도착 확인") { store.send(.arrivalTestTapped) }
                .font(.subheadline.bold()).padding(.horizontal, 16).padding(.vertical, 12)
                .foregroundStyle(.black)
                .background(store.isApproachingShelf ? BookNavigationPalette.accent : .white.opacity(0.75), in: Capsule())
                .accessibilityIdentifier("book-navigation-arrival-trigger")
            Spacer()
            Button { store.send(.recenterTapped) } label: { controlIcon("location.north.fill") }
                .accessibilityLabel("현재 위치로 지도 이동")
                .accessibilityIdentifier("book-navigation-recenter")
        }
        .buttonStyle(.plain)
    }

    private func controlIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 20, weight: .bold))
            .foregroundStyle(.black).frame(width: 48, height: 48)
            .background(.white.opacity(0.65), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
    }

    private func navigationMap(stop: BookNavigationStop, route: IndoorRoute, floor: IndoorMapFloor, height: CGFloat) -> some View {
        IndoorMapKitView(
            map: store.session.map, floor: floor, selectedFeatureID: nil,
            position: store.latestPosition, showsUserLocation: false, isPlacingOrigin: false,
            cameraRequest: store.cameraRequest, onSelect: { _ in }, onPlaceOrigin: { _ in },
            route: route, viewportInsets: .init(top: min(280, height * 0.35), left: 0, bottom: 90, right: 0),
            shelfLabels: [stop.shelf], highlightedFeatureIDs: [stop.shelf.mapElementID],
            routeTurnArrows: store.currentTurnArrows,
            navigationAppearance: true, navigationBearingRadians: store.navigationBearing,
            navigationDestination: store.currentPlan.map { .init(book: stop.book, coordinate: $0.destination.coordinate, floorID: stop.shelf.floorID) }
        )
        .accessibilityIdentifier("book-navigation-map")
    }
}
