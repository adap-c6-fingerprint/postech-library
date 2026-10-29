import ComposableArchitecture
import Foundation

/// 확정된 경로를 유지하며 위치 스트림·진행 계산·안내 표시를 연결한다.
@Reducer
struct BookNavigationFeature {
    enum ExitReason: Equatable, Sendable { case cancelled, completed }
    @ObservableState
    struct State: Equatable {
        // MARK: - 확정 경로와 구간별 표시 자료
        let session: BookNavigationSession
        let plans: [RouteGuidancePlan?]
        let bookInfos: [BookNavigationBookInfo?]
        let turnArrowsByStop: [[RouteTurnArrow]]
        // MARK: - 현재 진행과 위치 수신
        var currentStopIndex = 0
        var progress: RouteGuidanceProgress?
        var rawPosition: IndoorPosition?
        var latestPosition: IndoorPosition?
        var lastReceivedTimestamp: Date?
        var confirmedFloorOrdinal: Int?
        var authorization: IndoorLocationAuthorization = .notDetermined
        var statusMessage: String? = "현재 위치를 확인하고 있어요."
        var isActive = false
        var subscriptionID = 0
        // MARK: - 화면 전환과 카메라
        var isArrivalPresented = false
        var isCancelConfirmationPresented = false
        var exitReason: ExitReason?
        var cameraRequest: IndoorMapCameraRequest

        init(session: BookNavigationSession) {
            self.session = session
            let plans = session.legs.map { try? RouteGuidancePlan(route: $0, graph: session.graph) }
            self.plans = plans
            bookInfos = session.stops.indices.map { BookNavigationBookInfo(session: session, stopIndex: $0) }
            turnArrowsByStop = plans.map { plan in plan.map { RouteTurnArrow.make(from: $0) } ?? [] }
            cameraRequest = .init(id: 0, target: .route(session.legs.first ?? session.route,
                featureIDs: [session.origin.mapElementID] + session.stops.prefix(1).map { $0.shelf.mapElementID }))
        }

        var currentStop: BookNavigationStop? {
            session.stops.indices.contains(currentStopIndex) ? session.stops[currentStopIndex] : nil
        }
        var currentRoute: IndoorRoute? {
            session.legs.indices.contains(currentStopIndex) ? session.legs[currentStopIndex] : nil
        }
        var currentPlan: RouteGuidancePlan? {
            plans.indices.contains(currentStopIndex) ? plans[currentStopIndex] : nil
        }
        var currentBookInfo: BookNavigationBookInfo? {
            bookInfos.indices.contains(currentStopIndex) ? bookInfos[currentStopIndex] : nil
        }
        var currentTurnArrows: [RouteTurnArrow] {
            guard exitReason == nil else { return [] }
            guard turnArrowsByStop.indices.contains(currentStopIndex) else { return [] }
            let arrows = turnArrowsByStop[currentStopIndex]
            guard let progress else { return arrows }
            return arrows.filter { Double($0.stepIndex) >= Double(progress.stepIndex) + progress.fraction - 0.000_001 }
        }
        var remainingMetrics: BookNavigationMetrics? { remainingMeters.flatMap(BookNavigationMetrics.init) }
        var navigationBearing: Double? { progress.flatMap { currentPlan?.bearing(at: $0) } }
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
            if let ordinal = latestPosition?.floorOrdinal ?? confirmedFloorOrdinal {
                return session.map.floors.first { $0.ordinal == ordinal }
            }
            return session.map.floors.first { $0.id == currentRoute?.start.floorID }
        }
        var showsNativeUserLocation: Bool {
            isActive && authorization.isAuthorized && latestPosition?.source == .sensor
                && latestPosition?.floorOrdinal == currentFloor?.ordinal
        }
        var remainingMeters: Double? { progress?.remainingMeters }
        var instructionText: String? {
            guard let progress else { return nil }
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
            switch progress?.maneuver {
            case .left: "arrow.turn.up.left"
            case .right: "arrow.turn.up.right"
            case .turnAround: "arrow.uturn.backward"
            case .changeFloor: "arrow.up.arrow.down"
            case .nearDestination: "books.vertical"
            case .straight: "arrow.up"
            case nil: "location.slash"
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
        case requestLocationPermission
        case recenterTapped
        case arrivalTestTapped
        case arrivalPresentationChanged(Bool)
        case continueFromArrival(stopIndex: Int)
        case finishFromArrival(stopIndex: Int)
        case cancelTapped
        case cancelDismissed
        case cancelConfirmed
    }

    @Dependency(\.indoorLocationClient) var locationClient
    @Dependency(\.date.now) var now
    @Dependency(\.continuousClock) var clock
    private nonisolated enum CancelID: Hashable, Sendable { case location, expiry }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                guard state.exitReason == nil, !state.isActive else { return .none }
                return start(&state)

            case let .sceneActiveChanged(active):
                guard state.exitReason == nil, active != state.isActive else { return .none }
                return active ? start(&state) : stop(&state)

            case .disappeared:
                return stop(&state)

            case .recenterTapped:
                guard state.exitReason == nil else { return .none }
                if let position = state.latestPosition {
                    state.cameraRequest = .init(id: state.cameraRequest.id + 1, target: .position(position.coordinate))
                    return .none
                }
                if state.authorization == .notDetermined {
                    return .run { _ in await locationClient.requestPermission() }
                }
                state.statusMessage = "현재 위치를 확인한 뒤 지도를 이동할게요."
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
                if let floor = state.session.map.floors.first(where: { $0.ordinal == ordinal }) {
                    state.cameraRequest = .init(id: state.cameraRequest.id + 1, target: .floor(floor.id))
                }
                state.progress = nil
                if state.rawPosition != nil { updateGuidance(&state, previousTimestamp: nil) }
                return .none

            case .arrivalTestTapped:
                guard state.exitReason == nil, state.currentStop != nil, state.currentRoute != nil else { return .none }
                state.isArrivalPresented = true
                return .none

            case let .arrivalPresentationChanged(isPresented):
                state.isArrivalPresented = isPresented && state.exitReason == nil
                    && state.currentStop != nil && state.currentRoute != nil
                return .none

            case let .continueFromArrival(stopIndex):
                guard state.exitReason == nil, state.isArrivalPresented,
                      stopIndex == state.currentStopIndex, state.currentStop != nil, state.hasNextStop else { return .none }
                state.currentStopIndex += 1
                fitCurrentRoute(&state)
                state.isArrivalPresented = false
                state.progress = nil
                state.statusMessage = "다음 책까지의 위치를 확인하고 있어요."
                if state.rawPosition != nil { updateGuidance(&state, previousTimestamp: nil) }
                return .none

            case let .finishFromArrival(stopIndex):
                guard state.exitReason == nil, state.isArrivalPresented,
                      stopIndex == state.currentStopIndex, !state.hasNextStop,
                      state.currentStop != nil else { return .none }
                return end(&state, reason: .completed)

            case .cancelTapped:
                guard state.exitReason == nil else { return .none }
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

    private func start(_ state: inout State) -> Effect<Action> {
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
        state.exitReason = reason
        state.isArrivalPresented = false
        state.isCancelConfirmationPresented = false
        return stop(&state)
    }

    private func stop(_ state: inout State) -> Effect<Action> {
        state.isActive = false
        invalidate(&state, message: state.exitReason == nil ? "안내가 일시 정지됐어요." : "안내를 종료했어요.")
        return .merge(.cancel(id: CancelID.location), .cancel(id: CancelID.expiry))
    }

    private func invalidate(_ state: inout State, message: String) {
        state.rawPosition = nil
        state.latestPosition = nil
        state.progress = nil
        state.statusMessage = message
    }

    private func fitCurrentRoute(_ state: inout State) {
        guard let route = state.currentRoute, let stop = state.currentStop else { return }
        state.cameraRequest = .init(id: state.cameraRequest.id + 1,
            target: .route(route, featureIDs: [stop.shelf.mapElementID]))
    }

    private func updateGuidance(_ state: inout State, previousTimestamp: Date?) {
        guard let raw = state.rawPosition else { return }
        let ordinal = state.effectiveFloorOrdinal
        let effective = IndoorPosition(coordinate: raw.coordinate, floorOrdinal: ordinal,
            horizontalAccuracy: raw.horizontalAccuracy, timestamp: raw.timestamp, source: raw.source)
        guard let ordinal, state.session.map.floors.contains(where: { $0.ordinal == ordinal }) else {
            state.latestPosition = nil
            state.progress = nil
            state.statusMessage = raw.source == .simulation
                ? "시뮬레이터의 도면과 층을 확인해 주세요." : "현재 층을 선택해 주세요."
            return
        }
        let previousFloor = state.currentFloor?.id
        state.latestPosition = effective
        if previousFloor != state.currentFloor?.id { fitCurrentRoute(&state) }
        guard let plan = state.currentPlan else {
            state.progress = nil
            state.statusMessage = "경로 안내 데이터를 확인해 주세요."
            return
        }
        do {
            state.progress = try plan.progress(for: effective, at: now, previous: state.progress,
                elapsed: previousTimestamp.map { effective.timestamp.timeIntervalSince($0) })
            state.statusMessage = nil
        } catch {
            state.progress = nil
            switch error as? RouteGuidanceError {
            case .unknownFloor: state.statusMessage = "현재 층에는 안내 경로가 없어요. 층을 확인해 주세요."
            case .ambiguousPosition: state.statusMessage = "경로에서 현재 위치를 구분하기 어려워요. 위치를 다시 확인해 주세요."
            case .offRoute: state.statusMessage = "표시된 경로에서 벗어났어요. 위치와 층을 확인해 주세요."
            default:
                state.latestPosition = nil
                state.statusMessage = "현재 위치로 안내할 수 없어요. 새로운 위치 정보를 기다리고 있어요."
            }
        }
    }
}
