import Combine
import ComposableArchitecture
import Foundation

@Reducer
struct IndoorMapFeature {
    static let defaultFloorOrdinal = 2

    @ObservableState
    struct State: Equatable {
        let instanceID: UUID = { @Dependency(\.uuid) var uuid; return uuid() }()
        var homeAnnotations = HomeMapAnnotationsFeature.State()
        var map: IndoorMap?
        var isLoading = false
        var loadError: String?
        var navigation: IndoorNavigationData?
        var navigationLoadError: String?
        var isLoadingNavigation = false
        var navigationRequestID = 0
        var shelfLabels: [IndoorShelfLabel] = []
        var shelfLabelError: String?
        var isLoadingShelfLabels = false
        var shelfLabelRequestID = 0
        var selectedFloorID: UUID?
        var awaitsPositionFloor = true
        var lastSensedFloorOrdinal: Int?
        var selectedFeatureID: IndoorMapElement.ID?
        var selectedShelfKey: ShelfKey?
        var manualPosition: IndoorPosition?
        var latestPosition: IndoorPosition?
        var authorization: IndoorLocationAuthorization = .notDetermined
        var isPlacingOrigin = false
        var isActive = false
        var wantsRecenter = false
        var locationMessage: String?
        var cameraRequest: IndoorMapCameraRequest?
        var route: IndoorRoute?
        var routeDestinationKey: ShelfKey?
        var routePreference: RoutePreference = .shortestDistance
        var routeError: String?
        var isRouting = false
        var routeRequestID = 0
        var requiresStairConfirmation = false
        var isRouteSheetExpanded = false

        var routeDestination: ShelfDestination? {
            let key = selectedShelfKey ?? routeDestinationKey
            return navigation?.shelves.destinations.first { $0.key == key }
        }

        var routeSummary: String {
            if isRouting { return "서가까지의 경로를 찾고 있어요" }
            guard let route else { return "서가까지의 경로를 설정해요" }
            if route.startsAtDestinationNode { return "통로 연결 지점이 서가 도착점과 같아요" }
            return "\(route.usesEstimatedDistances ? "예상 거리" : "이동 거리") 약 \(route.distanceMeters.formatted(.number.precision(.fractionLength(0))))m"
        }

        var selectedFloor: IndoorMapFloor? { map?.floors.first { $0.id == selectedFloorID } }
        var selectedFeature: IndoorMapElement? { map?.features.first { $0.id == selectedFeatureID } }
        var currentPosition: IndoorPosition? { manualPosition ?? latestPosition }
        var mockShelves: [ShelfDestination] {
            navigation?.shelves.mode == .mock ? navigation?.shelves.destinations ?? [] : []
        }

        var showsNativeUserLocation: Bool {
            guard isActive, manualPosition == nil, authorization.isAuthorized,
                  latestPosition?.source == .sensor else { return false }
            if let currentFloor = latestPosition?.floorOrdinal, let viewedFloor = selectedFloor?.ordinal {
                return currentFloor == viewedFloor
            }
            return true
        }

        mutating func requestCamera(_ target: IndoorMapCameraRequest.Target) {
            cameraRequest = IndoorMapCameraRequest(id: (cameraRequest?.id ?? 0) + 1, target: target)
        }
    }

    enum Action: Equatable {
        case homeAnnotations(HomeMapAnnotationsFeature.Action)
        case task
        case retryTapped
        case mapLoaded(IndoorMap)
        case mapFailed(String)
        case retryNavigationTapped
        case navigationLoaded(requestID: Int, IndoorNavigationData)
        case navigationFailed(requestID: Int, String)
        case retryShelfLabelsTapped
        case shelfLabelsLoaded(requestID: Int, [IndoorShelfLabel])
        case shelfLabelsFailed(requestID: Int, String)
        case sceneActiveChanged(Bool)
        case disappeared
        case locationEvent(IndoorLocationEvent)
        case requestLocationPermission
        case currentLocationTapped
        case floorSelected(UUID)
        case fitMapTapped
        case manualOriginTapped
        case manualPointSelected(IndoorMapCoordinate)
        case manualFloorSelected(UUID)
        case featureSelected(IndoorMapElement.ID?)
        case shelfSelected(ShelfKey?)
        case routeSettingsTapped
        case routeSheetExpansionChanged(Bool)
        case routeRequested
        case routePreferenceChanged(RoutePreference)
        case routeLoaded(requestID: Int, IndoorRouteSearchOutcome)
        case routeFailed(requestID: Int, String)
        case routeCleared
        case useStairsTapped
        case dismissStairConfirmation
        case dismissMessage
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case showRouteSettings
        }
    }

    @Dependency(\.indoorMapClient) var mapClient
    @Dependency(\.indoorNavigationClient) var navigationClient
    @Dependency(\.indoorShelfLabelClient) var shelfLabelClient
    @Dependency(\.indoorLocationClient) var locationClient
    @Dependency(\.date.now) var now
    @Dependency(\.indoorRouteClient) var routeClient

    nonisolated private struct CancelID: Hashable, Sendable {
        enum Kind: Hashable, Sendable { case map, navigation, shelfLabels, location, route }
        let instance: UUID
        let kind: Kind

        init(_ instance: UUID, _ kind: Kind) {
            self.instance = instance
            self.kind = kind
        }
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.homeAnnotations, action: \.homeAnnotations) { HomeMapAnnotationsFeature() }
        Reduce { state, action in
            switch action {
            case .homeAnnotations:
                return .none
            case .task:
                state.isActive = true
                let loading = state.map == nil || state.loadError != nil ? loadMap(&state) : loadNavigation(&state)
                let labels = state.map != nil && state.shelfLabels.isEmpty && !state.isLoadingShelfLabels
                    ? loadShelfLabels(&state) : .none
                return .merge(loading, labels, locationEvents(state))

            case .retryTapped:
                return loadMap(&state)

            case .mapLoaded(let map):
                let cancellation = invalidateRoute(&state, clearDestination: true)
                state.isLoading = false
                state.loadError = nil
                state.map = map
                let reportedFloor = state.currentPosition?.floorOrdinal
                let positionFloor = map.floors.first { $0.ordinal == reportedFloor }
                let floor = positionFloor
                    ?? map.floors.first { $0.ordinal == Self.defaultFloorOrdinal }
                    ?? map.floors.first
                state.selectedFloorID = floor?.id
                state.awaitsPositionFloor = positionFloor == nil
                state.selectedFeatureID = nil
                state.selectedShelfKey = nil
                if let floor { state.requestCamera(.initialFloor(floor.id)) }
                state.navigation = nil
                state.isLoadingNavigation = false
                return .merge(cancellation, loadNavigation(&state), loadShelfLabels(&state))

            case .mapFailed(let message):
                state.isLoading = false
                state.loadError = message
                return .none

            case .retryNavigationTapped:
                return loadNavigation(&state)

            case .navigationLoaded(let requestID, let data):
                guard requestID == state.navigationRequestID else { return .none }
                let cancellation = invalidateRoute(&state, clearDestination: true)
                state.isLoadingNavigation = false
                state.navigationLoadError = nil
                state.navigation = data
                state.selectedShelfKey = nil
                return cancellation

            case .navigationFailed(let requestID, let message):
                guard requestID == state.navigationRequestID else { return .none }
                state.isLoadingNavigation = false
                state.navigationLoadError = message
                return .none

            case .retryShelfLabelsTapped:
                return loadShelfLabels(&state)

            case .shelfLabelsLoaded(let requestID, let labels):
                guard state.isLoadingShelfLabels, requestID == state.shelfLabelRequestID else { return .none }
                state.isLoadingShelfLabels = false
                state.shelfLabelError = nil
                state.shelfLabels = labels
                return .none

            case .shelfLabelsFailed(let requestID, let message):
                guard state.isLoadingShelfLabels, requestID == state.shelfLabelRequestID else { return .none }
                state.isLoadingShelfLabels = false
                state.shelfLabelError = message
                return .none

            case .sceneActiveChanged(let active):
                guard state.isActive != active else { return .none }
                state.isActive = active
                return active ? locationEvents(state) : .merge(.cancel(id: CancelID(state.instanceID, .location)), cancelRouteSearch(&state))

            case .disappeared:
                state.isActive = false
                if state.isLoadingShelfLabels {
                    state.isLoadingShelfLabels = false
                    state.shelfLabelRequestID += 1
                }
                if state.isLoadingNavigation {
                    state.isLoadingNavigation = false
                    state.navigationRequestID += 1
                }
                return .merge(.cancel(id: CancelID(state.instanceID, .location)), .cancel(id: CancelID(state.instanceID, .map)),
                              .cancel(id: CancelID(state.instanceID, .navigation)),
                              .cancel(id: CancelID(state.instanceID, .shelfLabels)), invalidateRoute(&state))

            case .locationEvent(.authorization(let authorization)):
                state.authorization = authorization
                if !authorization.isAuthorized {
                    state.latestPosition = nil
                    if authorization != .notDetermined { state.wantsRecenter = false }
                    return invalidateRoute(&state)
                }
                return .none

            case .locationEvent(.unavailable(let message)):
                state.latestPosition = nil
                guard state.manualPosition == nil else { return .none }
                if !state.isPlacingOrigin { state.locationMessage = message }
                return invalidateRoute(&state)

            case .locationEvent(.temporarilyUnavailable(let message)):
                state.latestPosition = nil
                guard state.manualPosition == nil, !state.isPlacingOrigin else { return .none }
                state.locationMessage = message
                return cancelRouteSearch(&state)

            case .locationEvent(.position(let position)):
                guard position.isRecent(at: now), position.source != .manual else { return .none }
                if let latest = state.latestPosition, position.timestamp < latest.timestamp { return .none }
                let previousFloor = state.latestPosition?.floorOrdinal
                state.latestPosition = position
                if state.manualPosition == nil && !state.isPlacingOrigin {
                    state.locationMessage = nil
                    let changedFloor = position.floorOrdinal != nil
                        && position.floorOrdinal != state.lastSensedFloorOrdinal
                    if let floorOrdinal = position.floorOrdinal { state.lastSensedFloorOrdinal = floorOrdinal }
                    if changedFloor || state.awaitsPositionFloor,
                       let floor = state.map?.floors.first(where: { $0.ordinal == position.floorOrdinal }) {
                        state.awaitsPositionFloor = false
                        if floor.id != state.selectedFloorID {
                            state.selectedFloorID = floor.id
                            state.selectedShelfKey = nil
                        }
                    }
                    if state.wantsRecenter { recenter(&state, position: position) }
                }
                if previousFloor != position.floorOrdinal && (state.isRouting || state.requiresStairConfirmation) {
                    return invalidateRoute(&state)
                }
                return .none

            case .requestLocationPermission:
                return .run { [locationClient] _ in await locationClient.requestPermission() }

            case .currentLocationTapped:
                state.manualPosition = nil
                state.isPlacingOrigin = false
                state.selectedFeatureID = nil
                state.locationMessage = nil
                switch state.authorization {
                case .notDetermined:
                    state.wantsRecenter = true
                    return .run { _ in await locationClient.requestPermission() }
                case .denied:
                    break
                case .restricted:
                    state.locationMessage = "기기 설정에서 위치 접근이 제한되어 있어요."
                case .servicesDisabled:
                    state.locationMessage = "기기의 위치 서비스가 꺼져 있어요. 설정에서 위치 서비스를 켜주세요."
                case .authorized:
                    if let position = state.latestPosition, position.isRecent(at: now) {
                        recenter(&state, position: position)
                    } else {
                        state.wantsRecenter = true
                        state.locationMessage = "현재 위치를 확인하고 있어요. 위치가 확인되면 지도를 이동할게요."
                    }
                }
                return .none

            case .floorSelected(let id):
                guard state.map?.floors.contains(where: { $0.id == id }) == true else { return .none }
                state.awaitsPositionFloor = false
                state.selectedFloorID = id
                state.selectedFeatureID = nil
                state.selectedShelfKey = nil
                return .none

            case .fitMapTapped:
                if let id = state.selectedFloorID { state.requestCamera(.floor(id)) }
                return .none

            case .manualOriginTapped:
                state.isPlacingOrigin.toggle()
                state.wantsRecenter = false
                state.selectedFeatureID = nil
                state.locationMessage = state.isPlacingOrigin ? "현재 층을 선택한 뒤 지도에서 출발점을 눌러주세요." : nil
                return .none

            case .manualPointSelected(let coordinate):
                guard let floor = state.selectedFloor, coordinate.isValid,
                      floor.geometry.contains(coordinate) else {
                    state.locationMessage = "선택한 층의 도면 안에서 출발점을 지정해주세요."
                    return .none
                }
                state.manualPosition = IndoorPosition(
                    coordinate: coordinate, floorOrdinal: floor.ordinal, horizontalAccuracy: nil,
                    timestamp: now, source: .manual
                )
                state.isPlacingOrigin = false
                state.wantsRecenter = false
                state.selectedFeatureID = nil
                state.locationMessage = nil
                state.requestCamera(.position(coordinate, revealsShelfNumbers: false))
                return .none

            case .manualFloorSelected(let id):
                guard let floor = state.map?.floors.first(where: { $0.id == id }) else { return .none }
                state.selectedFloorID = id
                state.selectedFeatureID = nil
                state.wantsRecenter = false
                if let position = state.currentPosition, position.isRecent(at: now),
                   floor.geometry.contains(position.coordinate) {
                    state.manualPosition = IndoorPosition(
                        coordinate: position.coordinate, floorOrdinal: floor.ordinal, horizontalAccuracy: nil,
                        timestamp: now, source: .manual
                    )
                    state.locationMessage = nil
                    state.isPlacingOrigin = false
                } else {
                    state.isPlacingOrigin = true
                    state.locationMessage = "현재 위치를 지정할 수 없어요. 선택한 층의 도면에서 출발점을 눌러주세요."
                }
                return .none

            case .featureSelected(let id):
                guard !state.isPlacingOrigin else { return .none }
                state.selectedFeatureID = id.flatMap { selected in
                    state.map?.features.first { $0.id == selected && $0.floorID == state.selectedFloorID }?.id
                }
                return .none

            case .shelfSelected(let key):
                state.selectedShelfKey = key.flatMap { key in
                    state.mockShelves.first { $0.key == key && $0.floorID == state.selectedFloorID }?.key
                }
                if let key = state.selectedShelfKey, key != state.routeDestinationKey {
                    return invalidateRoute(&state, clearDestination: true)
                }
                return .none

            case .routeRequested:
                return searchRoute(&state)

            case .routeSettingsTapped:
                guard let destination = state.routeDestination else { return .none }
                state.routeDestinationKey = destination.key
                state.isRouteSheetExpanded = false
                return .send(.delegate(.showRouteSettings))

            case .routeSheetExpansionChanged(let isExpanded):
                state.isRouteSheetExpanded = isExpanded
                return .none

            case .routePreferenceChanged(let preference):
                guard state.routePreference != preference else { return .none }
                state.routePreference = preference
                return state.routeDestinationKey == nil ? invalidateRoute(&state) : searchRoute(&state)

            case .routeLoaded(let requestID, let outcome):
                guard state.isRouting, state.routeRequestID == requestID else { return .none }
                state.isRouting = false
                switch outcome {
                case .route(let route): state.route = route
                case .requiresStairConfirmation: state.requiresStairConfirmation = true
                }
                return .none

            case .routeFailed(let requestID, let message):
                guard state.isRouting, state.routeRequestID == requestID else { return .none }
                state.isRouting = false
                state.routeError = message
                return .none

            case .useStairsTapped:
                guard state.requiresStairConfirmation else { return .none }
                return searchRoute(&state, allowingStairs: true)

            case .dismissStairConfirmation:
                state.requiresStairConfirmation = false
                return .none

            case .routeCleared:
                state.selectedShelfKey = nil
                state.isRouteSheetExpanded = false
                return invalidateRoute(&state, clearDestination: true)

            case .dismissMessage:
                state.locationMessage = nil
                return .none

            case .delegate:
                return .none
            }
        }
    }

    private func cancelRouteSearch(_ state: inout State) -> Effect<Action> {
        guard state.isRouting || state.requiresStairConfirmation else { return .none }
        state.routeRequestID += 1
        state.isRouting = false
        state.requiresStairConfirmation = false
        return .cancel(id: CancelID(state.instanceID, .route))
    }

    private func invalidateRoute(_ state: inout State, clearDestination: Bool = false) -> Effect<Action> {
        guard state.isRouting || state.route != nil || state.routeError != nil || state.requiresStairConfirmation
                || (clearDestination && state.routeDestinationKey != nil) else { return .none }
        state.routeRequestID += 1
        state.isRouting = false
        state.route = nil
        state.routeError = nil
        state.requiresStairConfirmation = false
        if clearDestination { state.routeDestinationKey = nil }
        return .cancel(id: CancelID(state.instanceID, .route))
    }

    private func searchRoute(_ state: inout State, allowingStairs: Bool = false) -> Effect<Action> {
        guard let data = state.navigation, let key = state.routeDestination?.key else { return .none }
        state.route = nil
        state.routeError = nil
        state.requiresStairConfirmation = false
        state.routeDestinationKey = key
        state.routeRequestID += 1
        let requestID = state.routeRequestID
        guard state.isActive, let position = state.currentPosition, position.isRecent(at: now) else {
            state.isRouting = false
            state.routeError = IndoorRoutingError.invalidPosition.localizedDescription
            return .cancel(id: CancelID(state.instanceID, .route))
        }
        state.isRouting = true
        let request = IndoorRouteRequest(navigation: data, start: position, destination: key,
            preference: state.routePreference, allowsStairFallback: allowingStairs)
        return .run { send in
            do { await send(.routeLoaded(requestID: requestID, try await routeClient.search(request))) }
            catch is CancellationError { }
            catch { await send(.routeFailed(requestID: requestID, error.localizedDescription)) }
        }.cancellable(id: CancelID(state.instanceID, .route), cancelInFlight: true)
    }

    private func loadMap(_ state: inout State) -> Effect<Action> {
        guard state.map == nil || state.loadError != nil else { return .none }
        state.isLoading = true
        state.loadError = nil
        return .run { send in
            do { await send(.mapLoaded(try await mapClient.load())) }
            catch is CancellationError { }
            catch { await send(.mapFailed(error.localizedDescription)) }
        }.cancellable(id: CancelID(state.instanceID, .map), cancelInFlight: true)
    }

    private func loadShelfLabels(_ state: inout State) -> Effect<Action> {
        state.shelfLabels = []
        state.shelfLabelError = nil
        guard let map = state.map, shelfLabelClient.supports(map) else {
            state.isLoadingShelfLabels = false
            return .cancel(id: CancelID(state.instanceID, .shelfLabels))
        }
        state.isLoadingShelfLabels = true
        state.shelfLabelRequestID += 1
        let requestID = state.shelfLabelRequestID
        return .run { send in
            do {
                let labels = try await shelfLabelClient.load(map)
                try Task.checkCancellation()
                await send(.shelfLabelsLoaded(requestID: requestID, labels))
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled else { return }
                await send(.shelfLabelsFailed(requestID: requestID, error.localizedDescription))
            }
        }.cancellable(id: CancelID(state.instanceID, .shelfLabels), cancelInFlight: true)
    }

    private func locationEvents(_ state: State) -> Effect<Action> {
        .run { send in
            @Shared(.indoorLocation) var location
            var previous: IndoorLocationSnapshot?
            for await snapshot in $location.publisher.values {
                guard !Task.isCancelled else { return }
                for event in snapshot.events(since: previous) { await send(.locationEvent(event)) }
                previous = snapshot
            }
        }.cancellable(id: CancelID(state.instanceID, .location), cancelInFlight: true)
    }

    private func loadNavigation(_ state: inout State) -> Effect<Action> {
        guard let map = state.map, state.navigation == nil, !state.isLoadingNavigation else { return .none }
        state.isLoadingNavigation = true
        state.navigationLoadError = nil
        state.navigationRequestID += 1
        let requestID = state.navigationRequestID
        return .run { send in
            do {
                let data = try await navigationClient.load(map)
                try Task.checkCancellation()
                await send(.navigationLoaded(requestID: requestID, data))
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled else { return }
                await send(.navigationFailed(requestID: requestID, error.localizedDescription))
            }
        }.cancellable(id: CancelID(state.instanceID, .navigation), cancelInFlight: true)
    }

    private func recenter(_ state: inout State, position: IndoorPosition) {
        if let ordinal = position.floorOrdinal,
           let floor = state.map?.floors.first(where: { $0.ordinal == ordinal }) {
            if state.selectedFloorID != floor.id { state.selectedShelfKey = nil }
            state.selectedFloorID = floor.id
            state.awaitsPositionFloor = false
        }
        state.requestCamera(.position(position.coordinate, revealsShelfNumbers: true))
        state.wantsRecenter = false
        state.locationMessage = nil
    }
}
