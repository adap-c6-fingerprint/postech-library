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
        var shelfLabels: [IndoorShelfLabel] = []
        var shelfLabelError: String?
        var isLoadingShelfLabels = false
        var shelfLabelRequestID = 0
        var selectedFloorID: UUID?
        var isFloorSelectedByUser = false
        var awaitsPositionFloor = true
        var lastSensedFloorOrdinal: Int?
        var latestPosition: IndoorPosition?
        var authorization: IndoorLocationAuthorization = .notDetermined
        var isActive = false
        var wantsRecenter = false
        var locationMessage: String?
        var cameraRequest: IndoorMapCameraRequest?

        var selectedFloor: IndoorMapFloor? { map?.floors.first { $0.id == selectedFloorID } }
        var currentPosition: IndoorPosition? { latestPosition }
        var positionFloorOrdinal: Int? {
            guard let latestPosition,
                  map?.groundFootprint?.contains(latestPosition.coordinate) == true else { return nil }
            return latestPosition.floorOrdinal
        }
        var showsNativeUserLocation: Bool {
            guard isActive, authorization.isAuthorized,
                  let latestPosition, latestPosition.source == .sensor,
                  map?.groundFootprint?.contains(latestPosition.coordinate) == true else { return false }
            if let currentFloor = latestPosition.floorOrdinal, let viewedFloor = selectedFloor?.ordinal {
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
        case retryShelfLabelsTapped
        case shelfLabelsLoaded(requestID: Int, [IndoorShelfLabel])
        case shelfLabelsFailed(requestID: Int, String)
        case sceneActiveChanged(Bool)
        case disappeared
        case locationEvent(IndoorLocationEvent)
        case requestLocationPermission
        case currentLocationTapped
        case floorSelected(UUID)
    }

    @Dependency(\.indoorMapClient) var mapClient
    @Dependency(\.indoorShelfLabelClient) var shelfLabelClient
    @Dependency(\.indoorLocationClient) var locationClient
    @Dependency(\.date.now) var now

    nonisolated private struct CancelID: Hashable, Sendable {
        enum Kind: Hashable, Sendable { case map, shelfLabels, location }
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
                let loading = state.map == nil || state.loadError != nil ? loadMap(&state) : .none
                let labels = state.map != nil && state.shelfLabels.isEmpty && !state.isLoadingShelfLabels
                    ? loadShelfLabels(&state) : .none
                return .merge(loading, labels, locationEvents(state))

            case .retryTapped:
                return loadMap(&state)

            case .mapLoaded(let map):
                state.isLoading = false
                state.loadError = nil
                state.map = map
                let reportedFloor = state.currentPosition?.isRecent(at: now) == true ? state.positionFloorOrdinal : nil
                let positionFloor = map.floors.first { $0.ordinal == reportedFloor }
                let selectedFloor = state.isFloorSelectedByUser ? state.selectedFloor : nil
                let floor = selectedFloor ?? positionFloor
                    ?? map.floors.first { $0.ordinal == Self.defaultFloorOrdinal }
                    ?? map.floors.first
                state.selectedFloorID = floor?.id
                state.awaitsPositionFloor = !state.isFloorSelectedByUser && positionFloor == nil
                if let floor { state.requestCamera(.initialFloor(floor.id)) }
                return loadShelfLabels(&state)

            case .mapFailed(let message):
                state.isLoading = false
                state.loadError = message
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
                return active ? locationEvents(state) : .cancel(id: CancelID(state.instanceID, .location))

            case .disappeared:
                state.isActive = false
                if state.isLoadingShelfLabels {
                    state.isLoadingShelfLabels = false
                    state.shelfLabelRequestID += 1
                }
                return .merge(.cancel(id: CancelID(state.instanceID, .location)), .cancel(id: CancelID(state.instanceID, .map)),
                              .cancel(id: CancelID(state.instanceID, .shelfLabels)))

            case .locationEvent(.authorization(let authorization)):
                state.authorization = authorization
                if !authorization.isAuthorized {
                    state.latestPosition = nil
                    if authorization != .notDetermined { state.wantsRecenter = false }
                }
                return .none

            case .locationEvent(.unavailable(let message)), .locationEvent(.temporarilyUnavailable(let message)):
                state.latestPosition = nil
                state.locationMessage = message
                return .none

            case .locationEvent(.position(let position)):
                guard position.isRecent(at: now), position.source != .manual else { return .none }
                if let latest = state.latestPosition, position.timestamp < latest.timestamp { return .none }
                state.latestPosition = position
                state.locationMessage = nil
                let ordinal = state.positionFloorOrdinal
                let changedFloor = ordinal != state.lastSensedFloorOrdinal
                state.lastSensedFloorOrdinal = ordinal
                if !state.isFloorSelectedByUser, changedFloor || state.awaitsPositionFloor,
                   let floor = state.map?.floors.first(where: { $0.ordinal == (ordinal ?? Self.defaultFloorOrdinal) }) {
                    state.awaitsPositionFloor = ordinal == nil
                    state.selectedFloorID = floor.id
                }
                if state.wantsRecenter { recenter(&state, position: position) }
                return .none

            case .requestLocationPermission:
                return .run { [locationClient] _ in await locationClient.requestPermission() }

            case .currentLocationTapped:
                state.isFloorSelectedByUser = false
                state.awaitsPositionFloor = true
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
                state.isFloorSelectedByUser = true
                state.wantsRecenter = false
                state.selectedFloorID = id
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

    private func recenter(_ state: inout State, position: IndoorPosition) {
        let ordinal = state.positionFloorOrdinal ?? Self.defaultFloorOrdinal
        if let floor = state.map?.floors.first(where: { $0.ordinal == ordinal }) {
            state.selectedFloorID = floor.id
            state.awaitsPositionFloor = false
        }
        if state.map?.groundFootprint?.contains(position.coordinate) == true {
            state.requestCamera(.position(position.coordinate, revealsShelfNumbers: true))
        } else if let floorID = state.selectedFloorID {
            state.requestCamera(.floor(floorID))
        }
        state.wantsRecenter = false
        state.locationMessage = nil
    }
}
