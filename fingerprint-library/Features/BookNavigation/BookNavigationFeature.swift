import Combine
import ComposableArchitecture
import Foundation
import UIKit

@Reducer
struct BookNavigationFeature {
    static let offRouteRerouteDelay: TimeInterval = 5

    typealias ExitReason = NavigationSession.Outcome
    enum SpinePhase: Equatable {
        case loading
        case loaded(UIImage)
        case unavailable
    }
    @ObservableState
    struct State: Equatable {
        var navigation: NavigationSession
        var routePlan: RoutePlan { navigation.routePlan }
        var currentStopIndex: Int { navigation.currentStopIndex }
        var exitReason: ExitReason? { navigation.outcome }
        var analyticsIsTest = false
        var plans: [GuidanceEngine?]
        let bookInfos: [BookNavigationBookInfo?]
        var turnArrowsByStop: [[RouteTurnArrow]]
        var timeline: BookNavigationTimeline
        var isReroutingToNextBook = false
        var offRouteSince: Date?
        var isReroutingCurrentStop = false
        var isReturningToPreviousStop = false
        var previousStopRequestID = 0
        var rerouteRequestID = 0
        var nextBookRequestID = 0
        var nextBookRouteError: String?
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
        var isCancelConfirmationPresented = false
        var cameraRequest: IndoorMapCameraRequest
        var followsNavigationCamera = true
        var cameraTracking = BookNavigationCameraTracking()
        var arrivalSpines: [Int: SpinePhase] = [:]

        init(routePlan: RoutePlan) {
            navigation = NavigationSession(routePlan: routePlan)
            let plans = routePlan.legs.map { try? GuidanceEngine(route: $0, graph: routePlan.graph) }
            self.plans = plans
            timeline = .init(plans: plans, bookCount: routePlan.stops.count)
            bookInfos = routePlan.stops.indices.map { BookNavigationBookInfo(routePlan: routePlan, stopIndex: $0) }
            turnArrowsByStop = plans.map { plan in plan.map { RouteTurnArrow.make(from: $0) } ?? [] }
            cameraRequest = .init(id: 0, target: .route(routePlan.legs.first ?? routePlan.route,
                featureIDs: routePlan.stops.prefix(1).map { $0.shelf.mapElementID }))
        }

        var canMarkShelfFound: Bool {
            exitReason == nil && !isArrivalPresented && !isReroutingToNextBook && !isReturningToPreviousStop
                && currentStop != nil && currentRoute != nil
        }
        var canReturnToPreviousStop: Bool {
            exitReason == nil && !isArrivalPresented && !isReroutingToNextBook && !isReturningToPreviousStop
                && navigation.hasPreviousStop
        }
        var currentStop: RouteStop? { navigation.currentStop }
        var currentRoute: IndoorRoute? { navigation.currentLeg }
        var currentPlan: GuidanceEngine? {
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
            return routePlan.map.floors.first { $0.ordinal == floor }?.id == currentStop?.shelf.floorID
        }
        var hasNextStop: Bool { navigation.hasNextStop }
        var effectiveFloorOrdinal: Int? {
            guard let rawPosition else { return confirmedFloorOrdinal }
            if let reported = rawPosition.floorOrdinal,
               routePlan.map.floors.contains(where: { $0.ordinal == reported }) { return reported }
            return rawPosition.source == .sensor ? confirmedFloorOrdinal : rawPosition.floorOrdinal
        }
        var canConfirmCurrentFloor: Bool {
            guard let rawPosition else { return true }
            return rawPosition.source == .sensor && !routePlan.map.floors.contains { $0.ordinal == rawPosition.floorOrdinal }
        }
        var currentFloor: IndoorMapFloor? {
            if let transition = manuallyCompletedFloorTransition, !transition.isReached(by: progress) {
                return routePlan.map.floors.first { $0.id == transition.to.floorID }
            }
            if let ordinal = latestPosition?.floorOrdinal ?? confirmedFloorOrdinal {
                return routePlan.map.floors.first { $0.ordinal == ordinal }
            }
            return routePlan.map.floors.first { $0.id == currentRoute?.start.floorID }
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
                let floor = routePlan.map.floors.first { $0.id == floorID }?.name ?? "안내된 층"
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
        case shelfFoundTapped
        case previousStopTapped
        case previousStopRouteLoaded(requestID: Int, stopIndex: Int, IndoorRoute)
        case previousStopRouteFailed(requestID: Int)
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
        case currentStopRerouted(requestID: Int, stopIndex: Int, IndoorRoute)
        case currentStopRerouteFailed(requestID: Int)
    }

    @Dependency(\.indoorLocationClient) var locationClient
    @Dependency(\.date.now) var now
    @Dependency(\.continuousClock) var clock
    @Dependency(\.bookCoverClient) var bookCoverClient
    @Dependency(\.routePlanningClient) var routePlanningClient
    @Dependency(\.analyticsClient) private var analytics
    private nonisolated enum CancelID: Hashable, Sendable { case location, expiry, nextBookRoute, reroute, previousStopRoute }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                guard state.exitReason == nil, !state.isActive else { return .none }
                let stopIndices = state.routePlan.stops.indices
                let spines = loadArrivalSpines(&state, stopIndices: stopIndices)
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
                    state.cameraRequest = .init(id: state.cameraRequest.id + 1, target: .position(position.coordinate, revealsShelfNumbers: false))
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
                          (-2...GuidanceEngine.maximumPositionAge).contains(now.timeIntervalSince(position.timestamp)) else {
                        invalidate(&state, message: "새로운 위치 정보를 기다리고 있어요.")
                        return .cancel(id: CancelID.expiry)
                    }
                    state.lastReceivedTimestamp = position.timestamp
                    guard accuracy <= GuidanceEngine.maximumAccuracyMeters else {
                        invalidate(&state, message: "위치 오차가 커서 안내를 잠시 멈췄어요.")
                        return .cancel(id: CancelID.expiry)
                    }
                    let previousTimestamp = state.rawPosition?.timestamp
                    state.rawPosition = position
                    updateGuidance(&state, previousTimestamp: previousTimestamp)
                    let delay = GuidanceEngine.maximumPositionAge - now.timeIntervalSince(position.timestamp)
                    let timestamp = position.timestamp
                    let expiry: Effect<Action> = .run { [clock] send in
                        try await clock.sleep(for: .seconds(max(0, delay)))
                        await send(.locationExpired(subscriptionID: subscriptionID, timestamp: timestamp))
                    }.cancellable(id: CancelID.expiry, cancelInFlight: true)
                    return .merge(expiry, rerouteIfOffRoute(&state))
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
                      state.routePlan.map.floors.contains(where: { $0.ordinal == ordinal }) else { return .none }
                state.confirmedFloorOrdinal = ordinal
                state.manuallyCompletedFloorTransition = nil
                if let floor = state.routePlan.map.floors.first(where: { $0.ordinal == ordinal }) {
                    state.cameraRequest = .init(id: state.cameraRequest.id + 1, target: .floor(floor.id))
                }
                state.progress = nil
                if state.rawPosition != nil { updateGuidance(&state, previousTimestamp: nil) }
                return .none

            case let .floorTransitionTapped(stopIndex, stepIndex):
                guard state.exitReason == nil, !state.isCancelConfirmationPresented,
                      state.currentStopIndex == stopIndex, let transition = state.nextFloorTransition,
                      transition.id == stepIndex,
                      state.routePlan.map.floors.contains(where: { $0.id == transition.to.floorID }) else { return .none }
                state.manuallyCompletedFloorTransition = transition
                state.confirmedFloorOrdinal = transition.to.level
                state.progress = nil
                state.followsNavigationCamera = true
                fitCurrentRoute(&state)
                return .none

            case .shelfFoundTapped:
                guard state.canMarkShelfFound else { return .none }
                state.isArrivalPresented = true
                state.navigation.markArrived()
                return .none

            case let .arrivalPresentationChanged(isPresented):
                state.isArrivalPresented = isPresented && state.exitReason == nil
                    && state.currentStop != nil && state.currentRoute != nil
                return .none

            case let .arrivalSpineTask(stopIndex):
                guard state.routePlan.stops.indices.contains(stopIndex) else { return .none }
                return loadArrivalSpines(&state, stopIndices: [stopIndex])

            case let .arrivalSpineLoaded(stopIndex, image):
                state.arrivalSpines[stopIndex] = image.map(SpinePhase.loaded) ?? .unavailable
                return .none

            case let .continueFromArrival(stopIndex):
                guard state.exitReason == nil, state.isArrivalPresented,
                      stopIndex == state.currentStopIndex, state.currentStop != nil, state.hasNextStop else { return .none }
                state.navigation.advance()
                state.offRouteSince = nil
                state.manuallyCompletedFloorTransition = nil
                state.followsNavigationCamera = true
                fitCurrentRoute(&state)
                state.isArrivalPresented = false
                state.progress = nil
                state.statusMessage = "다음 책까지의 위치를 확인하고 있어요."
                if state.rawPosition != nil { updateGuidance(&state, previousTimestamp: nil) }
                return .none

            case .nextBookTapped:
                guard state.exitReason == nil, state.hasNextStop, !state.isReroutingToNextBook,
                      !state.isReturningToPreviousStop else { return .none }
                state.isCancelConfirmationPresented = false
                state.nextBookRouteError = nil
                guard let position = state.latestPosition, position.isRecent(at: now),
                      (-2...GuidanceEngine.maximumPositionAge).contains(now.timeIntervalSince(position.timestamp)) else {
                    state.nextBookRouteError = "현재 위치를 확인한 뒤 다시 시도해 주세요."
                    return .none
                }
                let nextIndex = state.currentStopIndex + 1
                let nextStop = state.routePlan.stops[nextIndex]
                let destination = RouteCandidateStop(book: nextStop.book, holdings: nextStop.holdings,
                    candidateShelves: [nextStop.shelf])
                let map = state.routePlan.map, labels = state.routePlan.shelfLabels
                state.nextBookRequestID += 1
                let requestID = state.nextBookRequestID
                state.isReroutingToNextBook = true
                state.progress = nil
                state.statusMessage = "현재 위치에서 다음 책까지의 경로를 계산하고 있어요."
                return .run { [routePlanningClient] send in
                    do {
                        let routePlan = try await routePlanningClient.plan(map, labels, position, [destination])
                        try Task.checkCancellation()
                        guard let route = routePlan.legs.first else { throw IndoorRoutingError.noRoute }
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
                guard let plan = try? GuidanceEngine(route: route, graph: state.routePlan.graph),
                      state.navigation.replaceLeg(at: stopIndex, with: route) else {
                    state.nextBookRouteError = "다음 책의 경로를 확인할 수 없어요. 다시 시도해 주세요."
                    return .none
                }
                state.plans[stopIndex] = plan
                state.turnArrowsByStop[stopIndex] = RouteTurnArrow.make(from: plan)
                state.timeline = .init(plans: state.plans, bookCount: state.routePlan.stops.count)
                state.navigation.advance()
                state.offRouteSince = nil
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

            case .previousStopTapped:
                guard state.canReturnToPreviousStop else { return .none }
                state.isCancelConfirmationPresented = false
                let previousIndex = state.currentStopIndex - 1
                guard let position = state.latestPosition, position.source == .sensor, position.isRecent(at: now),
                      (-2...GuidanceEngine.maximumPositionAge).contains(now.timeIntervalSince(position.timestamp)) else {
                    moveToStop(&state, previousIndex)
                    return .cancel(id: CancelID.reroute)
                }
                let stop = state.routePlan.stops[previousIndex]
                let destination = RouteCandidateStop(book: stop.book, holdings: stop.holdings,
                                                         candidateShelves: [stop.shelf])
                let map = state.routePlan.map, labels = state.routePlan.shelfLabels
                state.previousStopRequestID += 1
                let requestID = state.previousStopRequestID
                state.isReturningToPreviousStop = true
                state.progress = nil
                state.statusMessage = "현재 위치에서 이전 서가까지의 경로를 계산하고 있어요."
                return .merge(.cancel(id: CancelID.reroute), .run { [routePlanningClient] send in
                    do {
                        let routePlan = try await routePlanningClient.plan(map, labels, position, [destination])
                        try Task.checkCancellation()
                        guard let route = routePlan.legs.first else { throw IndoorRoutingError.noRoute }
                        await send(.previousStopRouteLoaded(requestID: requestID, stopIndex: previousIndex, route))
                    } catch is CancellationError {
                        return
                    } catch {
                        await send(.previousStopRouteFailed(requestID: requestID))
                    }
                }.cancellable(id: CancelID.previousStopRoute, cancelInFlight: true))

            case let .previousStopRouteLoaded(requestID, stopIndex, route):
                guard state.isReturningToPreviousStop, requestID == state.previousStopRequestID,
                      state.exitReason == nil, stopIndex == state.currentStopIndex - 1 else { return .none }
                state.isReturningToPreviousStop = false
                if let plan = try? GuidanceEngine(route: route, graph: state.routePlan.graph),
                   state.navigation.replaceLeg(at: stopIndex, with: route) {
                    state.plans[stopIndex] = plan
                    state.turnArrowsByStop[stopIndex] = RouteTurnArrow.make(from: plan)
                    state.timeline = .init(plans: state.plans, bookCount: state.routePlan.stops.count)
                }
                moveToStop(&state, stopIndex)
                return .none

            case let .previousStopRouteFailed(requestID):
                guard state.isReturningToPreviousStop, requestID == state.previousStopRequestID,
                      state.exitReason == nil else { return .none }
                state.isReturningToPreviousStop = false
                moveToStop(&state, state.currentStopIndex - 1)
                return .none

            case let .currentStopRerouted(requestID, stopIndex, route):
                guard state.isReroutingCurrentStop, requestID == state.rerouteRequestID,
                      state.exitReason == nil else { return .none }
                state.isReroutingCurrentStop = false
                state.offRouteSince = nil
                guard stopIndex == state.currentStopIndex,
                      state.routePlan.legs.indices.contains(stopIndex),
                      let plan = try? GuidanceEngine(route: route, graph: state.routePlan.graph),
                      state.navigation.replaceLeg(at: stopIndex, with: route) else { return .none }
                state.plans[stopIndex] = plan
                state.turnArrowsByStop[stopIndex] = RouteTurnArrow.make(from: plan)
                state.timeline = .init(plans: state.plans, bookCount: state.routePlan.stops.count)
                state.manuallyCompletedFloorTransition = nil
                state.followsNavigationCamera = true
                state.progress = nil
                fitCurrentRoute(&state)
                state.statusMessage = "현재 위치에서 경로를 다시 찾았어요."
                recordQuality(state, code: "rerouted")
                if state.rawPosition != nil { updateGuidance(&state, previousTimestamp: nil) }
                return .none

            case let .currentStopRerouteFailed(requestID):
                guard state.isReroutingCurrentStop, requestID == state.rerouteRequestID else { return .none }
                state.isReroutingCurrentStop = false
                state.offRouteSince = state.latestPosition?.timestamp
                state.statusMessage = "경로를 다시 찾지 못했어요. 표시된 경로 쪽으로 이동해 주세요."
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
                guard state.exitReason == nil else { return .none }
                return end(&state, reason: .cancelled)
            }
        }
    }

    private func loadArrivalSpines(_ state: inout State, stopIndices: some Sequence<Int>) -> Effect<Action> {
        var requests: [(stopIndex: Int, isbn: String)] = []
        for stopIndex in stopIndices where state.arrivalSpines[stopIndex] == nil {
            if let isbn = state.routePlan.stops[stopIndex].book.isbn, let image = bookCoverClient.cachedSpineImage(isbn) {
                state.arrivalSpines[stopIndex] = .loaded(image)
            } else if let isbn = state.routePlan.stops[stopIndex].book.isbn {
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
    }

    private func start(_ state: inout State) -> Effect<Action> {
        if state.subscriptionID == 0 {
            analytics.record(.init(.navigationStarted, [
                .navigationID: .text(state.routePlan.id.uuidString),
                .bookCount: .integer(state.routePlan.stops.count),
                .distanceM: .decimal(state.routePlan.route.distanceMeters),
                .stepCount: .integer(state.routePlan.guidance.stepCount),
                .isTest: .flag(isAnalyticsTest(state))
            ]))
        }
        state.isActive = true
        state.subscriptionID += 1
        invalidate(&state, message: "현재 위치를 확인하고 있어요.")
        let id = state.subscriptionID
        return .merge(
            .run { send in
                @Shared(.indoorLocation) var location
                var previous: IndoorLocationSnapshot?
                for await snapshot in $location.publisher.values {
                    guard !Task.isCancelled else { return }
                    for event in snapshot.events(since: previous) {
                        await send(.locationEvent(subscriptionID: id, event))
                    }
                    previous = snapshot
                }
                guard !Task.isCancelled else { return }
                await send(.locationStreamEnded(subscriptionID: id))
            }.cancellable(id: CancelID.location, cancelInFlight: true),
            .run { _ in await locationClient.requestPermission() }
        )
    }

    private func end(_ state: inout State, reason: ExitReason) -> Effect<Action> {
        analytics.record(.init(reason == .completed ? .navigationCompleted : .navigationCancelled, [
            .navigationID: .text(state.routePlan.id.uuidString),
            .stopIndex: .integer(state.currentStopIndex), .isTest: .flag(isAnalyticsTest(state))
        ]))
        state.navigation.finish(reason)
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
        if state.isReroutingCurrentStop {
            state.isReroutingCurrentStop = false
            state.rerouteRequestID += 1
        }
        if state.isReturningToPreviousStop {
            state.isReturningToPreviousStop = false
            state.previousStopRequestID += 1
        }
        invalidate(&state, message: state.exitReason == nil ? "안내가 일시 정지됐어요." : "안내를 종료했어요.")
        return .merge(.cancel(id: CancelID.location), .cancel(id: CancelID.expiry), .cancel(id: CancelID.nextBookRoute),
                      .cancel(id: CancelID.reroute), .cancel(id: CancelID.previousStopRoute))
    }

    private func invalidate(_ state: inout State, message: String) {
        state.offRouteSince = nil
        state.rawPosition = nil
        state.latestPosition = nil
        state.progress = nil
        state.statusMessage = message
        state.cameraTracking = .init()
    }

    private func rerouteIfOffRoute(_ state: inout State) -> Effect<Action> {
        guard let since = state.offRouteSince, state.exitReason == nil, state.isActive,
              !state.isReroutingCurrentStop, !state.isReroutingToNextBook, !state.isReturningToPreviousStop,
              !state.isArrivalPresented,
              let position = state.latestPosition, position.source == .sensor, position.isRecent(at: now),
              position.timestamp.timeIntervalSince(since) >= Self.offRouteRerouteDelay,
              let stop = state.currentStop else { return .none }
        let stopIndex = state.currentStopIndex
        let destination = RouteCandidateStop(book: stop.book, holdings: stop.holdings,
                                                 candidateShelves: [stop.shelf])
        let map = state.routePlan.map, labels = state.routePlan.shelfLabels
        state.rerouteRequestID += 1
        let requestID = state.rerouteRequestID
        state.isReroutingCurrentStop = true
        state.statusMessage = "경로를 벗어나 현재 위치에서 경로를 다시 찾고 있어요."
        return .run { [routePlanningClient] send in
            do {
                let routePlan = try await routePlanningClient.plan(map, labels, position, [destination])
                try Task.checkCancellation()
                guard let route = routePlan.legs.first else { throw IndoorRoutingError.noRoute }
                await send(.currentStopRerouted(requestID: requestID, stopIndex: stopIndex, route))
            } catch is CancellationError {
                return
            } catch {
                await send(.currentStopRerouteFailed(requestID: requestID))
            }
        }.cancellable(id: CancelID.reroute, cancelInFlight: true)
    }

    private func moveToStop(_ state: inout State, _ stopIndex: Int) {
        guard state.routePlan.stops.indices.contains(stopIndex) else { return }
        state.navigation.move(to: stopIndex)
        state.offRouteSince = nil
        state.manuallyCompletedFloorTransition = nil
        state.followsNavigationCamera = true
        state.isArrivalPresented = false
        state.progress = nil
        fitCurrentRoute(&state)
        state.statusMessage = "이전 서가까지의 위치를 확인하고 있어요."
        if state.rawPosition != nil { updateGuidance(&state, previousTimestamp: nil) }
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
        guard let ordinal, state.routePlan.map.floors.contains(where: { $0.ordinal == ordinal }) else {
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
            state.offRouteSince = nil
            if !state.isReroutingCurrentStop { state.statusMessage = nil }
            recordQuality(state, code: "on_route")
            if let progress = state.progress {
                analytics.record(.init(.navigationStepChanged, [
                    .navigationID: .text(state.routePlan.id.uuidString),
                    .stepIndex: .integer(progress.stepIndex), .stopIndex: .integer(state.currentStopIndex),
                    .isTest: .flag(isAnalyticsTest(state))
                ]))
            }
            if state.isActive, state.exitReason == nil,
               state.progress?.maneuver == .nearDestination,
               state.navigation.markArrived() {
                state.isArrivalPresented = true
                analytics.record(.init(.destinationArrivalDetected, [
                    .navigationID: .text(state.routePlan.id.uuidString),
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
            case .offRoute:
                if state.offRouteSince == nil { state.offRouteSince = effective.timestamp }
                if !state.isReroutingCurrentStop {
                    state.statusMessage = "표시된 경로에서 벗어났어요. 위치와 층을 확인해 주세요."
                }
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
        state.analyticsIsTest || state.routePlan.start.source == .replay
    }

    private func recordQuality(_ state: State, code: String) {
        analytics.record(.init(.navigationQualityChanged, [
            .navigationID: .text(state.routePlan.id.uuidString), .qualityState: .text(code),
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
