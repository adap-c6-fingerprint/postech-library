import ComposableArchitecture
import Foundation
import UIKit

/// 확정된 경로를 유지하며 위치 스트림·진행 계산·안내 표시를 연결한다.
@Reducer
struct BookNavigationFeature {
    enum ExitReason: Equatable, Sendable { case cancelled, completed }
    enum SpinePhase: Equatable {
        case loading
        // 책등 이미지를 받는 중
        case loaded(UIImage)
        // 받은 책등 이미지. 표지와 같은 메모리 캐시(BookCoverPipeline.shared)에 있는 이미지 그대로다.
        case unavailable
        // ISBN이 없거나 책등 이미지를 받지 못한 책
    }
    @ObservableState
    struct State: Equatable {
        let session: BookNavigationSession
        var analyticsIsTest = false
        var plans: [RouteGuidancePlan?]
        let bookInfos: [BookNavigationBookInfo?]
        var turnArrowsByStop: [[RouteTurnArrow]]
        var timeline: BookNavigationTimeline
        var reroutedLegs: [Int: IndoorRoute] = [:]
        var isReroutingToNextBook = false
        var nextBookRequestID = 0
        var nextBookRouteError: String?
        var currentStopIndex = 0
        var progress: RouteGuidanceProgress?
        var manuallyCompletedFloorTransition: BookNavigationFloorTransition?
        var rawPosition: IndoorPosition?
        var latestPosition: IndoorPosition?
        var lastReceivedTimestamp: Date?
        var confirmedFloorOrdinal: Int?
        var authorization: IndoorLocationAuthorization = .notDetermined
        var statusMessage: String? = "현재 위치를 확인하고 있어요."
        var isActive = false
        var subscriptionID = 0
        var isArrivalPresented = false
        var isSheetExpanded = false
        var automaticallyArrivedStopIndices: Set<Int> = []
        var isCancelConfirmationPresented = false
        var exitReason: ExitReason?
        var cameraRequest: IndoorMapCameraRequest
        var followsNavigationCamera = true
        var cameraTracking = BookNavigationCameraTracking()
        var arrivalSpines: [Int: SpinePhase] = [:]
        // 책장 앞 책찾기 화면에 그릴 책등. 키는 목적지 순서(stopIndex)

        init(session: BookNavigationSession) {
            self.session = session
            let plans = session.legs.map { try? RouteGuidancePlan(route: $0, graph: session.graph) }
            self.plans = plans
            timeline = .init(plans: plans, bookCount: session.stops.count)
            bookInfos = session.stops.indices.map { BookNavigationBookInfo(session: session, stopIndex: $0) }
            turnArrowsByStop = plans.map { plan in plan.map { RouteTurnArrow.make(from: $0) } ?? [] }
            cameraRequest = .init(id: 0, target: .route(session.legs.first ?? session.route,
                featureIDs: session.stops.prefix(1).map { $0.shelf.mapElementID }))
        }

        var currentStop: BookNavigationStop? {
            session.stops.indices.contains(currentStopIndex) ? session.stops[currentStopIndex] : nil
        }
        var currentRoute: IndoorRoute? {
            reroutedLegs[currentStopIndex]
                ?? (session.legs.indices.contains(currentStopIndex) ? session.legs[currentStopIndex] : nil)
        }
        var currentPlan: RouteGuidancePlan? {
            plans.indices.contains(currentStopIndex) ? plans[currentStopIndex] : nil
        }
        var currentBookInfo: BookNavigationBookInfo? {
            bookInfos.indices.contains(currentStopIndex) ? bookInfos[currentStopIndex] : nil
        }
        var displayedProgress: RouteGuidanceProgress? {
            guard let manuallyCompletedFloorTransition, let plan = currentPlan else { return progress }
            return manuallyCompletedFloorTransition.displayedProgress(in: plan, liveProgress: progress)
        }
        var nextFloorTransition: BookNavigationFloorTransition? {
            guard exitReason == nil, !isArrivalPresented, !isReroutingToNextBook,
                  let plan = currentPlan else { return nil }
            return .next(in: plan, after: displayedProgress)
        }
        var currentTurnArrows: [RouteTurnArrow] {
            guard exitReason == nil else { return [] }
            guard turnArrowsByStop.indices.contains(currentStopIndex) else { return [] }
            let arrows = turnArrowsByStop[currentStopIndex]
            guard let progress = displayedProgress else { return arrows }
            return arrows.filter { Double($0.stepIndex) >= Double(progress.stepIndex) + progress.fraction - 0.000_001 }
        }
        var remainingMetrics: BookNavigationMetrics? { remainingMeters.flatMap(BookNavigationMetrics.init) }
        var navigationBearing: Double? { displayedProgress.flatMap { currentPlan?.bearing(at: $0) } }
        var isApproachingShelf: Bool {
            guard let progress, let meters = progress.remainingMeters, meters <= 8,
                  let floor = latestPosition?.floorOrdinal else { return false }
            switch progress.maneuver {
            case .straight, .nearDestination: break
            default: return false
            }
            return session.map.floors.first { $0.ordinal == floor }?.id == currentStop?.shelf.floorID
        }
        var hasNextStop: Bool { currentStopIndex >= 0 && currentStopIndex < session.stops.count - 1 }
        var effectiveFloorOrdinal: Int? {
            guard let rawPosition else { return confirmedFloorOrdinal }
            if let reported = rawPosition.floorOrdinal,
               session.map.floors.contains(where: { $0.ordinal == reported }) { return reported }
            return rawPosition.source == .sensor ? confirmedFloorOrdinal : rawPosition.floorOrdinal
        }
        var canConfirmCurrentFloor: Bool {
            guard let rawPosition else { return true }
            return rawPosition.source == .sensor && !session.map.floors.contains { $0.ordinal == rawPosition.floorOrdinal }
        }
        var currentFloor: IndoorMapFloor? {
            if let transition = manuallyCompletedFloorTransition, !transition.isReached(by: progress) {
                return session.map.floors.first { $0.id == transition.to.floorID }
            }
            if let ordinal = latestPosition?.floorOrdinal ?? confirmedFloorOrdinal {
                return session.map.floors.first { $0.ordinal == ordinal }
            }
            return session.map.floors.first { $0.id == currentRoute?.start.floorID }
        }
        var showsNativeUserLocation: Bool {
            isActive && authorization.isAuthorized && latestPosition?.source == .sensor
                && latestPosition?.floorOrdinal == currentFloor?.ordinal
        }
        var remainingMeters: Double? { displayedProgress?.remainingMeters }
        var instructionText: String? {
            guard let progress = displayedProgress else { return nextFloorTransition?.instructionText }
            let prefix = progress.distanceToManeuver.flatMap { meters in
                meters > 1 ? "약 \(meters.formatted(.number.precision(.fractionLength(0))))m 앞에서 " : nil
            } ?? ""
            switch progress.maneuver {
            case .straight: return "통로를 따라 이동하세요"
            case .left: return prefix + "좌회전하세요"
            case .right: return prefix + "우회전하세요"
            case .turnAround: return prefix + "방향을 돌려 이동하세요"
            case .nearDestination: return "목적지 서가 근처예요. 도착을 확인해 주세요"
            case let .changeFloor(category, floorID):
                let floor = session.map.floors.first { $0.id == floorID }?.name ?? "안내된 층"
                let facility: String = switch category {
                case .elevator: "엘리베이터"
                case .stairs: "계단"
                case .escalator: "에스컬레이터"
                case .ramp: "경사로"
                case .platformLift: "리프트"
                case .walkway: "연결 통로"
                }
                return prefix + "\(facility)로 \(floor)까지 이동하세요"
            }
        }
        var instructionSymbol: String {
            switch displayedProgress?.maneuver {
            case .left: "arrow.turn.up.left"
            case .right: "arrow.turn.up.right"
            case .turnAround: "arrow.uturn.backward"
            case .changeFloor: "arrow.up.arrow.down"
            case .nearDestination: "book"
            case .straight: "arrow.up"
            case nil: nextFloorTransition == nil ? "location.slash" : "arrow.up"
            }
        }
    }

    enum Action: Equatable {
        case task
        case sceneActiveChanged(Bool)
        case disappeared
        case locationEvent(subscriptionID: Int, IndoorLocationEvent)
        case locationStreamEnded(subscriptionID: Int)
        case locationExpired(subscriptionID: Int, timestamp: Date)
        case currentFloorConfirmed(Int)
        case floorTransitionTapped(stopIndex: Int, stepIndex: Int)
        case requestLocationPermission
        case recenterTapped
        case mapInteractionBegan
        case viewportChanged
        case sheetExpansionChanged(Bool)
        case arrivalTestTapped
        case arrivalPresentationChanged(Bool)
        case arrivalSpineTask(stopIndex: Int)
        case arrivalSpineLoaded(stopIndex: Int, UIImage?)
        case continueFromArrival(stopIndex: Int)
        case finishFromArrival(stopIndex: Int)
        case deferFromArrival(stopIndex: Int)
        case cancelTapped
        case cancelDismissed
        case cancelConfirmed
        case nextBookTapped
        case nextBookRouteLoaded(requestID: Int, stopIndex: Int, IndoorRoute)
        case nextBookRouteFailed(requestID: Int, String)
    }

    @Dependency(\.indoorLocationClient) var locationClient
    @Dependency(\.date.now) var now
    @Dependency(\.continuousClock) var clock
    @Dependency(\.bookCoverClient) var bookCoverClient
    @Dependency(\.bookRoutePreviewClient) var routePreviewClient
    @Dependency(\.analyticsClient) private var analytics
    private nonisolated enum CancelID: Hashable, Sendable { case location, expiry, nextBookRoute }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                guard state.exitReason == nil, !state.isActive else { return .none }
                let stopIndices = state.session.stops.indices
                let spines = loadArrivalSpines(&state, stopIndices: stopIndices)
                // 길안내를 시작하는 순간 모든 목적지의 책등을 준비해, 책찾기 화면이 로딩 없이 바로 그린다.
                return .merge(spines, start(&state))

            case let .sceneActiveChanged(active):
                guard state.exitReason == nil, active != state.isActive else { return .none }
                return active ? start(&state) : stop(&state)

            case .disappeared:
                return stop(&state)

            case .recenterTapped:
                guard state.exitReason == nil else { return .none }
                state.followsNavigationCamera = true
                if updateCamera(&state, force: true) { return .none }
                if let position = state.latestPosition,
                   state.manuallyCompletedFloorTransition == nil || position.floorOrdinal == state.currentFloor?.ordinal {
                    state.cameraRequest = .init(id: state.cameraRequest.id + 1, target: .position(position.coordinate, restoresInitialView: false))
                    return .none
                }
                if state.authorization == .notDetermined {
                    return .run { _ in await locationClient.requestPermission() }
                }
                state.statusMessage = "현재 위치를 확인한 뒤 지도를 이동할게요."
                return .none

            case .mapInteractionBegan:
                guard state.exitReason == nil else { return .none }
                state.followsNavigationCamera = false
                return .none

            case .viewportChanged:
                guard state.exitReason == nil, !state.isArrivalPresented, state.followsNavigationCamera else { return .none }
                if !updateCamera(&state, force: true) { fitCurrentRoute(&state) }
                return .none

            case let .sheetExpansionChanged(expanded):
                guard state.exitReason == nil, !state.isArrivalPresented else { return .none }
                state.isSheetExpanded = expanded
                return .none

            case .requestLocationPermission:
                guard state.exitReason == nil else { return .none }
                return .run { _ in await locationClient.requestPermission() }

            case let .locationEvent(subscriptionID, event):
                guard state.isActive, subscriptionID == state.subscriptionID else { return .none }
                switch event {
                case let .authorization(authorization):
                    state.authorization = authorization
                    switch authorization {
                    case .authorized(precise: true):
                        if state.progress == nil { state.statusMessage = "현재 위치를 확인하고 있어요." }
                        return .none
                    case .authorized(precise: false):
                        invalidate(&state, message: "설정에서 정확한 위치를 허용해 주세요.")
                    case .notDetermined:
                        invalidate(&state, message: "위치 권한을 허용하면 안내를 시작해요.")
                    case .denied, .restricted:
                        invalidate(&state, message: "설정에서 위치 접근을 허용해 주세요.")
                    case .servicesDisabled:
                        invalidate(&state, message: "기기의 위치 서비스를 켜 주세요.")
                    }
                    return .cancel(id: CancelID.expiry)

                case let .unavailable(message), let .temporarilyUnavailable(message):
                    invalidate(&state, message: message)
                    return .cancel(id: CancelID.expiry)

                case let .position(position):
                    guard state.authorization == .authorized(precise: true) else { return .none }
                    if let last = state.lastReceivedTimestamp, position.timestamp <= last { return .none }
                    guard position.source != .manual, position.coordinate.isValid,
                          let accuracy = position.horizontalAccuracy, accuracy.isFinite, accuracy >= 0,
                          (-2...RouteGuidancePlan.maximumPositionAge).contains(now.timeIntervalSince(position.timestamp)) else {
                        invalidate(&state, message: "새로운 위치 정보를 기다리고 있어요.")
                        return .cancel(id: CancelID.expiry)
                    }
                    state.lastReceivedTimestamp = position.timestamp
                    guard accuracy <= RouteGuidancePlan.maximumAccuracyMeters else {
                        invalidate(&state, message: "위치 오차가 커서 안내를 잠시 멈췄어요.")
                        return .cancel(id: CancelID.expiry)
                    }
                    let previousTimestamp = state.rawPosition?.timestamp
                    state.rawPosition = position
                    updateGuidance(&state, previousTimestamp: previousTimestamp)
                    let delay = RouteGuidancePlan.maximumPositionAge - now.timeIntervalSince(position.timestamp)
                    let timestamp = position.timestamp
                    return .run { [clock] send in
                        try await clock.sleep(for: .seconds(max(0, delay)))
                        await send(.locationExpired(subscriptionID: subscriptionID, timestamp: timestamp))
                    }.cancellable(id: CancelID.expiry, cancelInFlight: true)
                }

            case let .locationExpired(subscriptionID, timestamp):
                guard state.isActive, subscriptionID == state.subscriptionID,
                      state.rawPosition?.timestamp == timestamp else { return .none }
                invalidate(&state, message: "위치 수신이 멈췄어요. 다시 확인하고 있어요.")
                return .none

            case let .locationStreamEnded(subscriptionID):
                guard state.isActive, subscriptionID == state.subscriptionID else { return .none }
                invalidate(&state, message: "위치 연결이 종료됐어요. 안내 화면을 다시 열어 주세요.")
                return .cancel(id: CancelID.expiry)

            case let .currentFloorConfirmed(ordinal):
                guard state.exitReason == nil, state.canConfirmCurrentFloor,
                      state.session.map.floors.contains(where: { $0.ordinal == ordinal }) else { return .none }
                state.confirmedFloorOrdinal = ordinal
                state.manuallyCompletedFloorTransition = nil
                if let floor = state.session.map.floors.first(where: { $0.ordinal == ordinal }) {
                    state.cameraRequest = .init(id: state.cameraRequest.id + 1, target: .floor(floor.id))
                }
                state.progress = nil
                if state.rawPosition != nil { updateGuidance(&state, previousTimestamp: nil) }
                return .none

            case let .floorTransitionTapped(stopIndex, stepIndex):
                guard state.exitReason == nil, !state.isCancelConfirmationPresented,
                      state.currentStopIndex == stopIndex, let transition = state.nextFloorTransition,
                      transition.id == stepIndex,
                      state.session.map.floors.contains(where: { $0.id == transition.to.floorID }) else { return .none }
                state.manuallyCompletedFloorTransition = transition
                state.confirmedFloorOrdinal = transition.to.level
                // 실제 좌표는 그대로 두고 다음 층의 경로만 표시한다.
                state.progress = nil
                state.followsNavigationCamera = true
                fitCurrentRoute(&state)
                return .none

            case .arrivalTestTapped:
                guard state.exitReason == nil, state.currentStop != nil, state.currentRoute != nil else { return .none }
                state.isArrivalPresented = true
                return .none

            case let .arrivalPresentationChanged(isPresented):
                state.isArrivalPresented = isPresented && state.exitReason == nil
                    && state.currentStop != nil && state.currentRoute != nil
                return .none

            case let .arrivalSpineTask(stopIndex):
                guard state.session.stops.indices.contains(stopIndex) else { return .none }
                return loadArrivalSpines(&state, stopIndices: [stopIndex])
                // 길안내 시작 때 이미 준비했으면 아무것도 하지 않는다. 시작 때 상태가 없던 경우에만 받는다.

            case let .arrivalSpineLoaded(stopIndex, image):
                state.arrivalSpines[stopIndex] = image.map(SpinePhase.loaded) ?? .unavailable
                // spineImage는 "책등 없음"과 "실패"를 같은 에러로 던지므로 둘 다 준비 중 이미지로 그린다.
                return .none

            case let .continueFromArrival(stopIndex):
                guard state.exitReason == nil, state.isArrivalPresented,
                      stopIndex == state.currentStopIndex, state.currentStop != nil, state.hasNextStop else { return .none }
                state.currentStopIndex += 1
                state.manuallyCompletedFloorTransition = nil
                state.followsNavigationCamera = true
                fitCurrentRoute(&state)
                state.isArrivalPresented = false
                state.progress = nil
                state.statusMessage = "다음 책까지의 위치를 확인하고 있어요."
                if state.rawPosition != nil { updateGuidance(&state, previousTimestamp: nil) }
                return .none

            case .nextBookTapped:
                guard state.exitReason == nil, state.hasNextStop, !state.isReroutingToNextBook else { return .none }
                state.isCancelConfirmationPresented = false
                state.nextBookRouteError = nil
                guard let position = state.latestPosition, position.isRecent(at: now),
                      (-2...RouteGuidancePlan.maximumPositionAge).contains(now.timeIntervalSince(position.timestamp)) else {
                    state.nextBookRouteError = "현재 위치를 확인한 뒤 다시 시도해 주세요."
                    return .none
                }
                let nextIndex = state.currentStopIndex + 1
                let nextStop = state.session.stops[nextIndex]
                // 방문 순서와 이미 선택한 서가를 유지한다. 남은 책의 순서를 다시 최적화하지 않는다.
                let destination = BookRouteCandidateStop(book: nextStop.book, holdings: nextStop.holdings,
                    candidateShelves: [nextStop.shelf])
                let map = state.session.map, labels = state.session.shelfLabels
                state.nextBookRequestID += 1
                let requestID = state.nextBookRequestID
                state.isReroutingToNextBook = true
                state.progress = nil
                state.statusMessage = "현재 위치에서 다음 책까지의 경로를 계산하고 있어요."
                return .run { [routePreviewClient] send in
                    do {
                        let session = try await routePreviewClient.load(map, labels, position, [destination])
                        try Task.checkCancellation()
                        guard let route = session.legs.first else { throw IndoorRoutingError.noRoute }
                        await send(.nextBookRouteLoaded(requestID: requestID, stopIndex: nextIndex, route))
                    } catch is CancellationError {
                        return
                    } catch {
                        await send(.nextBookRouteFailed(requestID: requestID, error.localizedDescription))
                    }
                }.cancellable(id: CancelID.nextBookRoute, cancelInFlight: true)

            case let .nextBookRouteLoaded(requestID, stopIndex, route):
                guard state.isReroutingToNextBook, state.exitReason == nil,
                      requestID == state.nextBookRequestID, stopIndex == state.currentStopIndex + 1 else { return .none }
                state.isReroutingToNextBook = false
                guard route.destination == state.session.legs[stopIndex].destination,
                      let plan = try? RouteGuidancePlan(route: route, graph: state.session.graph) else {
                    state.nextBookRouteError = "다음 책의 경로를 확인할 수 없어요. 다시 시도해 주세요."
                    return .none
                }
                state.reroutedLegs[stopIndex] = route
                state.plans[stopIndex] = plan
                state.turnArrowsByStop[stopIndex] = RouteTurnArrow.make(from: plan)
                state.timeline = .init(plans: state.plans, bookCount: state.session.stops.count)
                state.currentStopIndex = stopIndex
                state.manuallyCompletedFloorTransition = nil
                state.followsNavigationCamera = true
                state.isArrivalPresented = false
                state.progress = nil
                fitCurrentRoute(&state)
                state.statusMessage = "다음 책까지의 위치를 확인하고 있어요."
                if state.rawPosition != nil { updateGuidance(&state, previousTimestamp: nil) }
                return .none

            case let .nextBookRouteFailed(requestID, message):
                guard state.isReroutingToNextBook, requestID == state.nextBookRequestID else { return .none }
                state.isReroutingToNextBook = false
                state.nextBookRouteError = "다음 책 경로를 계산하지 못했어요. \(message)"
                return .none

            case let .finishFromArrival(stopIndex):
                guard state.exitReason == nil, state.isArrivalPresented,
                      stopIndex == state.currentStopIndex, !state.hasNextStop,
                      state.currentStop != nil else { return .none }
                return end(&state, reason: .completed)

            case let .deferFromArrival(stopIndex):
                guard state.exitReason == nil, state.isArrivalPresented,
                      stopIndex == state.currentStopIndex, state.currentStop != nil else { return .none }
                return end(&state, reason: .cancelled)

            case .cancelTapped:
                guard state.exitReason == nil else { return .none }
                state.nextBookRouteError = nil
                state.isCancelConfirmationPresented = true
                return .none

            case .cancelDismissed:
                state.isCancelConfirmationPresented = false
                return .none

            case .cancelConfirmed:
                // Alert의 바인딩이 버튼 액션보다 먼저 닫혀도 확인 동작을 처리한다.
                guard state.exitReason == nil else { return .none }
                return end(&state, reason: .cancelled)
            }
        }
    }

    /// 아직 상태가 없는 목적지의 책등을 표지와 같은 메모리 캐시에서 꺼내거나 받는다.
    private func loadArrivalSpines(_ state: inout State, stopIndices: some Sequence<Int>) -> Effect<Action> {
        var requests: [(stopIndex: Int, isbn: String)] = []
        for stopIndex in stopIndices where state.arrivalSpines[stopIndex] == nil {
            if let isbn = state.session.stops[stopIndex].book.isbn, let image = bookCoverClient.cachedSpineImage(isbn) {
                state.arrivalSpines[stopIndex] = .loaded(image)
                // 상세·책바구니에서 안내를 시작할 때 미리 받아 둔 책등은 기다리지 않고 바로 쓴다.
            } else if let isbn = state.session.stops[stopIndex].book.isbn {
                state.arrivalSpines[stopIndex] = .loading
                requests.append((stopIndex, isbn))
            } else {
                state.arrivalSpines[stopIndex] = .unavailable
            }
        }
        guard !requests.isEmpty else { return .none }
        return .run { [bookCoverClient, requests] send in
            await withTaskGroup(of: Void.self) { group in
                for request in requests {
                    group.addTask {
                        let image = try? await bookCoverClient.spineImage(request.isbn)
                        await send(.arrivalSpineLoaded(stopIndex: request.stopIndex, image))
                    }
                }
            }
        }
        // 마이페이지 책장(RecentlyFoundBookFeature)과 같은 방식이다. 미리 받는 중인 책등은 진행 중 요청을 함께 쓴다.
    }

    private func start(_ state: inout State) -> Effect<Action> {
        if state.subscriptionID == 0 {
            analytics.record(.init(.navigationStarted, [
                .navigationID: .text(state.session.id.uuidString),
                .bookCount: .integer(state.session.stops.count),
                .distanceM: .decimal(state.session.route.distanceMeters),
                .stepCount: .integer(state.session.guidance.stepCount),
                .isTest: .flag(isAnalyticsTest(state))
            ]))
        }
        state.isActive = true
        state.subscriptionID += 1
        invalidate(&state, message: "현재 위치를 확인하고 있어요.")
        let id = state.subscriptionID
        return .merge(
            .run { [locationClient] send in
                for await event in await locationClient.events() {
                    guard !Task.isCancelled else { return }
                    await send(.locationEvent(subscriptionID: id, event))
                }
                guard !Task.isCancelled else { return }
                await send(.locationStreamEnded(subscriptionID: id))
            }.cancellable(id: CancelID.location, cancelInFlight: true),
            .run { _ in await locationClient.requestPermission() }
        )
    }

    private func end(_ state: inout State, reason: ExitReason) -> Effect<Action> {
        analytics.record(.init(reason == .completed ? .navigationCompleted : .navigationCancelled, [
            .navigationID: .text(state.session.id.uuidString),
            .stopIndex: .integer(state.currentStopIndex), .isTest: .flag(isAnalyticsTest(state))
        ]))
        state.exitReason = reason
        state.isArrivalPresented = false
        state.isCancelConfirmationPresented = false
        return stop(&state)
    }

    private func stop(_ state: inout State) -> Effect<Action> {
        state.isActive = false
        if state.isReroutingToNextBook {
            state.isReroutingToNextBook = false
            state.nextBookRequestID += 1
        }
        invalidate(&state, message: state.exitReason == nil ? "안내가 일시 정지됐어요." : "안내를 종료했어요.")
        return .merge(.cancel(id: CancelID.location), .cancel(id: CancelID.expiry), .cancel(id: CancelID.nextBookRoute))
    }

    private func invalidate(_ state: inout State, message: String) {
        state.rawPosition = nil
        state.latestPosition = nil
        state.progress = nil
        state.statusMessage = message
        state.cameraTracking = .init()
    }

    private func fitCurrentRoute(_ state: inout State) {
        state.cameraTracking = .init()
        guard let route = state.currentRoute, let stop = state.currentStop else { return }
        state.cameraRequest = .init(id: state.cameraRequest.id + 1,
            target: .route(route, featureIDs: stop.candidateShelves.map(\.mapElementID)))
    }

    private func updateGuidance(_ state: inout State, previousTimestamp: Date?) {
        guard let raw = state.rawPosition else { return }
        let ordinal = state.effectiveFloorOrdinal
        let effective = IndoorPosition(coordinate: raw.coordinate, floorOrdinal: ordinal,
            horizontalAccuracy: raw.horizontalAccuracy, timestamp: raw.timestamp, source: raw.source,
            headingDegrees: raw.headingDegrees)
        guard let ordinal, state.session.map.floors.contains(where: { $0.ordinal == ordinal }) else {
            state.latestPosition = nil
            state.progress = nil
            state.statusMessage = "현재 층을 선택해 주세요."
            state.cameraTracking = .init()
            return
        }
        let previousFloor = state.currentFloor?.id
        state.latestPosition = effective
        if state.isReroutingToNextBook {
            state.progress = nil
            state.statusMessage = "현재 위치에서 다음 책까지의 경로를 계산하고 있어요."
            return
        }
        if previousFloor != state.currentFloor?.id { fitCurrentRoute(&state) }
        guard let plan = state.currentPlan else {
            state.progress = nil
            state.statusMessage = "경로 안내 데이터를 확인해 주세요."
            state.cameraTracking = .init()
            return
        }
        do {
            state.progress = try plan.progress(for: effective, at: now, previous: state.progress,
                elapsed: previousTimestamp.map { effective.timestamp.timeIntervalSince($0) })
            if state.manuallyCompletedFloorTransition != nil, previousFloor != state.currentFloor?.id {
                fitCurrentRoute(&state)
            }
            state.statusMessage = nil
            recordQuality(state, code: "on_route")
            if let progress = state.progress {
                // Runtime에서 같은 경유지·edge step의 연속 GPS 갱신을 한 번으로 줄인다.
                analytics.record(.init(.navigationStepChanged, [
                    .navigationID: .text(state.session.id.uuidString),
                    .stepIndex: .integer(progress.stepIndex), .stopIndex: .integer(state.currentStopIndex),
                    .isTest: .flag(isAnalyticsTest(state))
                ]))
            }
            if state.isActive, state.exitReason == nil,
               state.progress?.maneuver == .nearDestination,
               state.automaticallyArrivedStopIndices.insert(state.currentStopIndex).inserted {
                state.isArrivalPresented = true
                analytics.record(.init(.destinationArrivalDetected, [
                    .navigationID: .text(state.session.id.uuidString),
                    .stopIndex: .integer(state.currentStopIndex), .isTest: .flag(isAnalyticsTest(state))
                ]))
            }
            updateCamera(&state)
        } catch {
            state.progress = nil
            state.cameraTracking = .init()
            switch error as? RouteGuidanceError {
            case .unknownFloor: state.statusMessage = "현재 층에는 안내 경로가 없어요. 층을 확인해 주세요."
            case .ambiguousPosition: state.statusMessage = "경로에서 현재 위치를 구분하기 어려워요. 위치를 다시 확인해 주세요."
            case .offRoute: state.statusMessage = "표시된 경로에서 벗어났어요. 위치와 층을 확인해 주세요."
            default:
                state.latestPosition = nil
                state.statusMessage = "현재 위치로 안내할 수 없어요. 새로운 위치 정보를 기다리고 있어요."
            }
            let code: String = switch error as? RouteGuidanceError {
            case .unknownFloor: "unknown_floor"
            case .ambiguousPosition: "ambiguous_position"
            case .offRoute: "off_route"
            default: "unusable_position"
            }
            recordQuality(state, code: code)
        }
    }

    private func isAnalyticsTest(_ state: State) -> Bool {
        state.analyticsIsTest || state.session.start.source == .replay
    }

    private func recordQuality(_ state: State, code: String) {
        analytics.record(.init(.navigationQualityChanged, [
            .navigationID: .text(state.session.id.uuidString), .qualityState: .text(code),
            .isTest: .flag(isAnalyticsTest(state))
        ]))
    }

    @discardableResult
    private func updateCamera(_ state: inout State, force: Bool = false) -> Bool {
        guard state.followsNavigationCamera, state.isActive, state.exitReason == nil,
              !state.isArrivalPresented, let position = state.latestPosition,
              let progress = state.progress, let plan = state.currentPlan,
              let floor = state.currentFloor,
              let focus = state.cameraTracking.focus(position: position, progress: progress,
                  plan: plan, floorID: floor.id, force: force) else { return false }
        state.cameraRequest = .init(id: state.cameraRequest.id + 1, target: .navigation(focus))
        return true
    }
}
