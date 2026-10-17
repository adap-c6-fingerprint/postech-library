import ComposableArchitecture
import Foundation

@Reducer
struct IndoorMapFeature {
    @ObservableState
    struct State: Equatable {
        var map: IndoorMap?
        var isLoading = false
        var loadError: String?
        var navigation: IndoorNavigationData?
        var navigationLoadError: String?
        var isLoadingNavigation = false
        var navigationRequestID = 0
        var selectedFloorID: UUID?
        var selectedFeatureID: IndoorMapElement.ID?
        var manualPosition: IndoorPosition?
        var latestPosition: IndoorPosition?
        var authorization: IndoorLocationAuthorization = .notDetermined
        var isPlacingOrigin = false
        var isActive = false
        var wantsRecenter = false
        var locationMessage: String?
        var cameraRequest: IndoorMapCameraRequest?

        var selectedFloor: IndoorMapFloor? { map?.floors.first { $0.id == selectedFloorID } }
        var selectedFeature: IndoorMapElement? { map?.features.first { $0.id == selectedFeatureID } }
        var currentPosition: IndoorPosition? { manualPosition ?? latestPosition }

        var showsNativeUserLocation: Bool {
            guard isActive, manualPosition == nil, authorization.isAuthorized,
                  latestPosition?.source != .replay else { return false }
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
        case task
        case retryTapped
        case mapLoaded(IndoorMap)
        case mapFailed(String)
        case retryNavigationTapped
        case navigationLoaded(requestID: Int, IndoorNavigationData)
        case navigationFailed(requestID: Int, String)
        case sceneActiveChanged(Bool)
        case disappeared
        case locationEvent(IndoorLocationEvent)
        case currentLocationTapped
        case floorSelected(UUID)
        case fitMapTapped
        case manualOriginTapped
        case manualPointSelected(IndoorMapCoordinate)
        case manualFloorSelected(UUID)
        case featureSelected(IndoorMapElement.ID?)
        case dismissMessage
    }

    @Dependency(\.indoorMapClient) var mapClient
    @Dependency(\.indoorNavigationClient) var navigationClient
    @Dependency(\.indoorLocationClient) var locationClient
    @Dependency(\.date.now) var now

    nonisolated private enum CancelID: Hashable, Sendable { case map, navigation, location }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                state.isActive = true
                let loading = state.map == nil || state.loadError != nil ? loadMap(&state) : loadNavigation(&state)
                return .merge(loading, locationEvents())

            case .retryTapped:
                return loadMap(&state)

            case .mapLoaded(let map):
                state.isLoading = false
                state.loadError = nil
                state.map = map
                let reportedFloor = state.currentPosition?.floorOrdinal
                let floor = map.floors.first { $0.ordinal == reportedFloor } ?? map.floors.first
                state.selectedFloorID = floor?.id
                state.selectedFeatureID = nil
                if let floor { state.requestCamera(.floor(floor.id)) }
                state.navigation = nil
                state.isLoadingNavigation = false
                return loadNavigation(&state)

            case .mapFailed(let message):
                state.isLoading = false
                state.loadError = message
                return .none

            case .retryNavigationTapped:
                return loadNavigation(&state)

            case .navigationLoaded(let requestID, let data):
                guard requestID == state.navigationRequestID else { return .none }
                state.isLoadingNavigation = false
                state.navigationLoadError = nil
                state.navigation = data
                return .none

            case .navigationFailed(let requestID, let message):
                guard requestID == state.navigationRequestID else { return .none }
                state.isLoadingNavigation = false
                state.navigationLoadError = message
                return .none

            case .sceneActiveChanged(let active):
                guard state.isActive != active else { return .none }
                state.isActive = active
                return active ? locationEvents() : .cancel(id: CancelID.location)

            case .disappeared:
                state.isActive = false
                if state.isLoadingNavigation {
                    state.isLoadingNavigation = false
                    state.navigationRequestID += 1
                }
                return .merge(.cancel(id: CancelID.location), .cancel(id: CancelID.map), .cancel(id: CancelID.navigation))

            case .locationEvent(.authorization(let authorization)):
                state.authorization = authorization
                if !authorization.isAuthorized {
                    state.latestPosition = nil
                    if authorization != .notDetermined { state.wantsRecenter = false }
                }
                return .none

            case .locationEvent(.unavailable(let message)):
                if state.manualPosition == nil && !state.isPlacingOrigin { state.locationMessage = message }
                return .none

            case .locationEvent(.position(let position)):
                guard position.isRecent(at: now), position.source != .manual else { return .none }
                if let latest = state.latestPosition, position.timestamp < latest.timestamp { return .none }
                state.latestPosition = position
                if state.manualPosition == nil && !state.isPlacingOrigin {
                    state.locationMessage = nil
                    if state.wantsRecenter { recenter(&state, position: position) }
                }
                return .none

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
                    state.locationMessage = "위치 권한이 꺼져 있어요. 설정에서 위치 접근을 허용하거나 출발점을 직접 지정해주세요."
                case .restricted:
                    state.locationMessage = "위치 접근이 제한되어 있어요. 층과 출발점을 직접 지정해주세요."
                case .servicesDisabled:
                    state.locationMessage = "기기의 위치 서비스가 꺼져 있어요. 위치 서비스를 켜거나 출발점을 직접 지정해주세요."
                case .authorized:
                    if let position = state.latestPosition, position.isRecent(at: now) {
                        recenter(&state, position: position)
                    } else {
                        state.wantsRecenter = true
                        state.locationMessage = "현재 위치를 확인하고 있어요. 위치가 잡히지 않으면 출발점을 직접 지정해주세요."
                    }
                }
                return .none

            case .floorSelected(let id):
                guard state.map?.floors.contains(where: { $0.id == id }) == true else { return .none }
                state.selectedFloorID = id
                state.selectedFeatureID = nil
                state.requestCamera(.floor(id))
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
                state.requestCamera(.position(coordinate))
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
                state.requestCamera(.floor(id))
                return .none

            case .featureSelected(let id):
                guard !state.isPlacingOrigin else { return .none }
                state.selectedFeatureID = id.flatMap { selected in
                    state.map?.features.first { $0.id == selected && $0.floorID == state.selectedFloorID }?.id
                }
                return .none

            case .dismissMessage:
                state.locationMessage = nil
                return .none
            }
        }
    }

    private func loadMap(_ state: inout State) -> Effect<Action> {
        guard state.map == nil || state.loadError != nil else { return .none }
        state.isLoading = true
        state.loadError = nil
        return .run { send in
            do { await send(.mapLoaded(try await mapClient.load())) }
            catch is CancellationError { }
            catch { await send(.mapFailed(error.localizedDescription)) }
        }.cancellable(id: CancelID.map, cancelInFlight: true)
    }

    private func locationEvents() -> Effect<Action> {
        .run { send in
            for await event in await locationClient.events() {
                guard !Task.isCancelled else { return }
                await send(.locationEvent(event))
            }
        }.cancellable(id: CancelID.location, cancelInFlight: true)
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
        }.cancellable(id: CancelID.navigation, cancelInFlight: true)
    }

    private func recenter(_ state: inout State, position: IndoorPosition) {
        if let ordinal = position.floorOrdinal,
           let floor = state.map?.floors.first(where: { $0.ordinal == ordinal }) {
            state.selectedFloorID = floor.id
        }
        state.requestCamera(.position(position.coordinate))
        state.wantsRecenter = false
        state.locationMessage = nil
    }
}

nonisolated struct IndoorMapCameraRequest: Equatable, Sendable {
    enum Target: Equatable, Sendable {
        case floor(UUID)
        case position(IndoorMapCoordinate)
    }
    let id: Int
    let target: Target
}
