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
                        currentFloorIndicator
                    }
                    .padding(.horizontal, 20).padding(.top, 20)
                    VStack(spacing: 16) {
                        Spacer()
                        HStack(spacing: 8) {
                            if store.canReturnToPreviousStop { previousShelfButton }
                            if store.canMarkShelfFound { shelfFoundButton }
                            Spacer(minLength: 0)
                            MapRecenterButton(accessibilityIdentifier: "book-navigation-recenter") {
                                store.send(.recenterTapped)
                            }
                        }
                        if let transition = store.nextFloorTransition {
                            floorTransitionButton(transition, stopIndex: store.currentStopIndex)
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
                    routePlan: store.routePlan, currentStopIndex: index,
                    bookInformation: store.currentBookInfo,
                    spine: store.arrivalSpines[index],
                    onTask: { store.send(.arrivalSpineTask(stopIndex: index)) },
                    onContinue: { store.send(.continueFromArrival(stopIndex: index)) },
                    onFinish: { store.send(.finishFromArrival(stopIndex: index)) },
                    onDefer: { store.send(.deferFromArrival(stopIndex: index)) },
                    onCancel: { store.send(.cancelTapped) }
                )
                .id(index)
            }
        }
        .interactiveDismissDisabled()
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
                .typography(.body2.weight(.semibold))
                .padding(.horizontal, 16)
                .frame(height: 48)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityHint("이전 책의 서가로 다시 안내해요")
        .accessibilityIdentifier("book-navigation-previous-shelf")
    }

    private var shelfFoundButton: some View {
        Button { store.send(.shelfFoundTapped) } label: {
            Label("서가를 찾았어요", systemImage: "checkmark")
                .typography(.body2.weight(.semibold))
                .padding(.horizontal, 18)
                .frame(height: 48)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityHint("책장 앞 책등 찾기 화면으로 이동해요")
        .accessibilityIdentifier("book-navigation-shelf-found")
    }

    private var guidanceSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: store.instructionSymbol)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 23, height: 23)
                        .background(.black, in: Circle())
                        .accessibilityHidden(true)
                    Text(store.nextBookRouteError ?? store.instructionText ?? store.statusMessage ?? "현재 위치를 확인하고 있어요.")
                        .typography(.body1).lineLimit(2)
                        .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 28)
                .accessibilityIdentifier("book-navigation-instruction")
                BookNavigationProgressBar(timeline: store.timeline, stopIndex: store.currentStopIndex,
                    progress: store.displayedProgress, floors: store.routePlan.map.floors)
            }
            .padding(.horizontal, 16)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if abs(height - sheetSummaryHeight) > 0.5 { sheetSummaryHeight = height }
            }
            if isSheetExpanded {
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                    .padding(.horizontal, 14).padding(.top, 20)
                    .accessibilityHidden(true)
                if let info = store.currentBookInfo, let route = store.currentRoute {
                    BookNavigationCurrentBookCard(info: info, route: route)
                        .padding(.horizontal, 16).padding(.top, 24)
                        .id(store.currentStopIndex)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                .typography(.caption2.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
                .padding(.horizontal, 16)
                .frame(minHeight: 34)
                .glassEffect(.regular.tint(.black.opacity(0.2)), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("book-navigation-floor-transition")
        .accessibilityHint("\(store.routePlan.map.floors.first { $0.id == transition.to.floorID }?.name ?? "다음 층") 경로를 표시합니다")
    }

    private func navigationMap(stop: RouteStop, route: IndoorRoute, floor: IndoorMapFloor) -> some View {
        IndoorMapKitView(
            map: store.routePlan.map, floor: floor, selectedFeatureID: nil,
            position: store.latestPosition, showsUserLocation: false, isPlacingOrigin: false,
            cameraRequest: store.cameraRequest, onSelect: { _ in }, onPlaceOrigin: { _ in },
            route: route, viewportInsets: .init(top: 140, left: 0,
                bottom: sheetHeight + (store.nextFloorTransition == nil ? 0 : 50), right: 0),
            shelfLabels: stop.candidateShelves, highlightedFeatureIDs: Set(stop.candidateShelves.map(\.mapElementID)),
            navigationAppearance: true,
            navigationDestination: store.currentPlan.map { .init(book: stop.book, coordinate: $0.destination.coordinate, floorID: stop.shelf.floorID) },
            onUserCameraInteraction: { store.send(.mapInteractionBegan) }
        )
        .accessibilityIdentifier("book-navigation-map")
    }
}
