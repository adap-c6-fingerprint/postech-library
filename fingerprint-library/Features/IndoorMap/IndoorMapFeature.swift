import ComposableArchitecture
import Foundation

/// 지도 로딩·층 조회·위치 수신·단일 서가 경로 요청을 연결하는 TCA 기능.
///
/// 파일과 위치 시스템은 Clients를 통해 사용하고, MapKit 객체는 View에서 관리한다.
/// 지도와 navigation 로딩 상태를 분리해 노드 자료가 준비되지 않아도 지도를 표시한다.
@Reducer
struct IndoorMapFeature {
    /// 지도 화면에 필요한 값 상태. 표시 중인 층과 실제 위치의 층은 서로 다를 수 있다.
    @ObservableState
    struct State: Equatable {
        /// 검증을 마친 도면. navigation의 성공 여부와 독립적으로 유지한다.
        var map: IndoorMap?
        var isLoading = false
        var loadError: String?
        /// 도면에 맞춰 읽은 노드·서가·거리 자료. 자료 준비 전이나 로딩 실패 시 nil이다.
        var navigation: IndoorNavigationData?
        /// 길찾기 자료 준비 전·실패 상태의 안내. 지도 자체의 loadError와 구분한다.
        var navigationLoadError: String?
        var isLoadingNavigation = false
        /// 현재 요청의 결과만 수용하기 위한 번호. 취소·재요청 뒤의 늦은 응답을 구분한다.
        var navigationRequestID = 0
        /// 지도에 표시할 번호·범위. 도착 노드가 없는 경우에도 별도로 읽는다.
        var shelfLabels: [IndoorShelfLabel] = []
        var shelfLabelError: String?
        var isLoadingShelfLabels = false
        var shelfLabelRequestID = 0
        /// 사용자가 조회하는 층의 원본 ID. 위치의 floorOrdinal을 덮어쓰는 값이 아니다.
        var selectedFloorID: UUID?
        var selectedFeatureID: IndoorMapElement.ID?
        var selectedShelfKey: ShelfKey?
        var manualPosition: IndoorPosition?
        var latestPosition: IndoorPosition?
        var authorization: IndoorLocationAuthorization = .notDetermined
        var isPlacingOrigin = false
        var isActive = false
        var wantsRecenter = false
        var locationMessage: String?
        /// 가장 최근의 지도 이동 의도. 실제 적용 여부는 View의 Coordinator가 별도로 기억한다.
        var cameraRequest: IndoorMapCameraRequest?
        var route: IndoorRoute?
        var routeDestinationKey: ShelfKey?
        var routePreference: RoutePreference = .shortestDistance
        var routeError: String?
        var isRouting = false
        /// 이전 경로 탐색의 늦은 성공·실패가 현재 상태를 덮어쓰지 않게 한다.
        var routeRequestID = 0
        var requiresStairConfirmation = false
        var isRouteSheetExpanded = false

        /// 새로 선택한 서가를 우선하고, 선택이 없으면 경로에 보관한 서가를 조회한다.
        var routeDestination: ShelfDestination? {
            let key = selectedShelfKey ?? routeDestinationKey
            return navigation?.shelves.destinations.first { $0.key == key }
        }

        /// 계산 상태와 거리 출처를 표시한다. 통로 연결점과 목적지가 같아도 실제 도착으로 단정하지 않는다.
        var routeSummary: String {
            if isRouting { return "서가까지의 경로를 찾고 있어요" }
            guard let route else { return "서가까지의 경로를 설정해요" }
            if route.startsAtDestinationNode { return "통로 연결 지점이 서가 도착점과 같아요" }
            return "\(route.usesEstimatedDistances ? "예상 거리" : "이동 거리") 약 \(route.distanceMeters.formatted(.number.precision(.fractionLength(0))))m"
        }

        var selectedFloor: IndoorMapFloor? { map?.floors.first { $0.id == selectedFloorID } }
        var selectedFeature: IndoorMapElement? { map?.features.first { $0.id == selectedFeatureID } }
        /// 내부 수동 위치 정책을 우선한 위치 후보. 탐색 시에는 별도로 유효 시간도 검사한다.
        var currentPosition: IndoorPosition? { manualPosition ?? latestPosition }
        /// 목업 모드로 명시된 목적지만 테스트용 서가 핀으로 표시한다.
        var mockShelves: [ShelfDestination] {
            navigation?.shelves.mode == .mock ? navigation?.shelves.destinations ?? [] : []
        }

        /// 센서 위치일 때만 MapKit 기본 사용자 위치를 켜 합성 위치 마커와 중복을 피한다.
        /// 실제 위치와 조회 층을 모두 아는 경우에는 같은 층에서만 표시한다.
        var showsNativeUserLocation: Bool {
            guard isActive, manualPosition == nil, authorization.isAuthorized,
                  latestPosition?.source == .sensor else { return false }
            if let currentFloor = latestPosition?.floorOrdinal, let viewedFloor = selectedFloor?.ordinal {
                return currentFloor == viewedFloor
            }
            return true
        }

        /// 같은 목적지의 재요청도 새 의도로 구분하도록 번호를 증가시켜 카메라 요청을 만든다.
        ///
        /// - Parameter target: 최초 확대 표시, 층 전체 맞춤 또는 특정 위치 중심 이동.
        mutating func requestCamera(_ target: IndoorMapCameraRequest.Target) {
            cameraRequest = IndoorMapCameraRequest(id: (cameraRequest?.id ?? 0) + 1, target: target)
        }
    }

    /// 사용자 조작과 Clients의 비동기 결과를 처리하고, 앱 전체 화면 이동은 delegate로 전달한다.
    enum Action: Equatable {
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

    nonisolated private enum CancelID: Hashable, Sendable { case map, navigation, shelfLabels, location, route }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                state.isActive = true
                let loading = state.map == nil || state.loadError != nil ? loadMap(&state) : loadNavigation(&state)
                let labels = state.map != nil && state.shelfLabels.isEmpty && !state.isLoadingShelfLabels
                    ? loadShelfLabels(&state) : .none
                return .merge(loading, labels, locationEvents())

            case .retryTapped:
                return loadMap(&state)

            case .mapLoaded(let map):
                let cancellation = invalidateRoute(&state, clearDestination: true)
                state.isLoading = false
                state.loadError = nil
                state.map = map
                let reportedFloor = state.currentPosition?.floorOrdinal
                let floor = map.floors.first { $0.ordinal == reportedFloor } ?? map.floors.first
                state.selectedFloorID = floor?.id
                state.selectedFeatureID = nil
                state.selectedShelfKey = nil
                if let position = state.latestPosition, position.source == .simulation,
                   !acceptsSimulation(position, on: map) {
                    state.latestPosition = nil
                    state.locationMessage = "시뮬레이터에서 앱과 같은 도면과 층을 선택해주세요."
                }
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
                return active ? locationEvents() : .merge(.cancel(id: CancelID.location), cancelRouteSearch(&state))

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
                return .merge(.cancel(id: CancelID.location), .cancel(id: CancelID.map),
                              .cancel(id: CancelID.navigation), .cancel(id: CancelID.shelfLabels), invalidateRoute(&state))

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
                if position.source == .simulation, let map = state.map, !acceptsSimulation(position, on: map) {
                    state.latestPosition = nil
                    state.locationMessage = "시뮬레이터에서 앱과 같은 도면과 층을 선택해주세요."
                    return invalidateRoute(&state)
                }
                let previousFloor = state.latestPosition?.floorOrdinal
                state.latestPosition = position
                if state.manualPosition == nil && !state.isPlacingOrigin {
                    state.locationMessage = nil
                    if position.source == .simulation, previousFloor != position.floorOrdinal,
                       let floor = state.map?.floors.first(where: { $0.ordinal == position.floorOrdinal }),
                       floor.id != state.selectedFloorID {
                        state.selectedFloorID = floor.id
                        state.selectedShelfKey = nil
                    }
                    if state.wantsRecenter { recenter(&state, position: position) }
                }
                if previousFloor != position.floorOrdinal && (state.isRouting || state.requiresStairConfirmation) {
                    return invalidateRoute(&state)
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
                    state.locationMessage = "위치 권한이 꺼져 있어요. 설정에서 위치 접근을 허용해주세요."
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
                state.selectedFloorID = id
                state.selectedFeatureID = nil
                state.selectedShelfKey = nil
                // 층별 외곽 크기가 달라도 사용자가 보고 있던 중심·줌·회전을 유지한다.
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

    /// 진행 중인 경로 탐색과 계단 확인만 취소하고 이미 계산한 미리보기는 보존한다.
    /// 일시적인 위치 수신 중단은 경로 자체를 무효화하는 사유와 구분한다.
    private func cancelRouteSearch(_ state: inout State) -> Effect<Action> {
        guard state.isRouting || state.requiresStairConfirmation else { return .none }
        state.routeRequestID += 1
        state.isRouting = false
        state.requiresStairConfirmation = false
        return .cancel(id: CancelID.route)
    }

    /// 이전 탐색 결과를 무효화하고 진행 중 작업·완료 경로·오류·계단 확인 상태를 정리한다.
    ///
    /// - Parameters:
    ///   - state: 정리할 화면 상태.
    ///   - clearDestination: 도면이나 선택 대상이 바뀌어 기존 목적지 키도 버려야 하는지 여부.
    private func invalidateRoute(_ state: inout State, clearDestination: Bool = false) -> Effect<Action> {
        guard state.isRouting || state.route != nil || state.routeError != nil || state.requiresStairConfirmation
                || (clearDestination && state.routeDestinationKey != nil) else { return .none }
        state.routeRequestID += 1
        state.isRouting = false
        state.route = nil
        state.routeError = nil
        state.requiresStairConfirmation = false
        if clearDestination { state.routeDestinationKey = nil }
        return .cancel(id: CancelID.route)
    }

    /// 활성 화면의 최근 위치와 선택한 서가로 경로 요청을 만들고 이전 요청을 취소한다.
    ///
    /// 위치가 유효하지 않으면 탐색 Client를 호출하지 않는다. 응답에는 요청 번호를 붙여
    /// 뒤늦은 결과가 새 요청에 섞이는 것을 막는다.
    /// - Parameters:
    ///   - state: 도면·navigation·출발 위치와 목적지를 가진 화면 상태.
    ///   - allowingStairs: 사용자가 계단 포함 재탐색을 확인했는지 여부.
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
            return .cancel(id: CancelID.route)
        }
        state.isRouting = true
        let request = IndoorRouteRequest(navigation: data, start: position, destination: key,
            preference: state.routePreference, allowsStairFallback: allowingStairs)
        return .run { send in
            do { await send(.routeLoaded(requestID: requestID, try await routeClient.search(request))) }
            catch is CancellationError { }
            catch { await send(.routeFailed(requestID: requestID, error.localizedDescription)) }
        }.cancellable(id: CancelID.route, cancelInFlight: true)
    }

    /// 합성 위치가 알려진 층과 그 층의 도면 경계 안에 있는지 확인한다.
    /// 도면 개정의 동일성, 벽 통과 여부, 실제 측위 정확도를 인증하는 검사는 아니다.
    private func acceptsSimulation(_ position: IndoorPosition, on map: IndoorMap) -> Bool {
        guard let floor = map.floors.first(where: { $0.ordinal == position.floorOrdinal }) else { return false }
        return floor.geometry.contains(position.coordinate)
    }

    /// 지도가 없거나 이전 로딩이 실패한 경우 도면 로딩을 시작하고 성공·실패 Action으로 전달한다.
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

    /// 서가 표시 자료만 갱신한다. 실패해도 지도·층 선택·길찾기 로딩을 유지한다.
    private func loadShelfLabels(_ state: inout State) -> Effect<Action> {
        state.shelfLabels = []
        state.shelfLabelError = nil
        guard let map = state.map, shelfLabelClient.supports(map) else {
            state.isLoadingShelfLabels = false
            return .cancel(id: CancelID.shelfLabels)
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
        }.cancellable(id: CancelID.shelfLabels, cancelInFlight: true)
    }

    /// 화면 수명에 맞춰 위치 스트림을 구독하고 재구독 시 이전 구독을 취소한다.
    private func locationEvents() -> Effect<Action> {
        .run { send in
            for await event in await locationClient.events() {
                guard !Task.isCancelled else { return }
                await send(.locationEvent(event))
            }
        }.cancellable(id: CancelID.location, cancelInFlight: true)
    }

    /// 지도 로딩 이후 그 지도에 맞는 길찾기 자료를 읽는다.
    ///
    /// 이미 자료가 있거나 읽는 중이면 중복 요청하지 않는다. 준비 전·실패 응답은 navigation 상태에만
    /// 반영하므로 도면을 유지할 수 있으며, 요청 번호로 이탈·재시도 이전의 응답을 구분한다.
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

    /// 호출부에서 수락한 현재 위치로 조회 층과 카메라를 이동하고 한 번의 포커싱 요청을 마친다.
    private func recenter(_ state: inout State, position: IndoorPosition) {
        if let ordinal = position.floorOrdinal,
           let floor = state.map?.floors.first(where: { $0.ordinal == ordinal }) {
            if state.selectedFloorID != floor.id { state.selectedShelfKey = nil }
            state.selectedFloorID = floor.id
        }
        state.requestCamera(.position(position.coordinate))
        state.wantsRecenter = false
        state.locationMessage = nil
    }
}

/// TCA에서 MapKit으로 전달하는 값 기반 카메라 이동 요청.
/// View는 요청 ID를 기억해 일반 상태 갱신이 사용자의 지도 이동을 덮어쓰지 않게 한다.
nonisolated struct IndoorMapCameraRequest: Equatable, Sendable {
    enum Target: Equatable, Sendable {
        /// 최초 표시 층의 중심을 기준으로 도면을 확대한다. 일반 층 전환에서는 요청하지 않는다.
        case initialFloor(UUID)
        /// 지정 층의 도형 전체를 표시 영역에 맞춘다.
        case floor(UUID)
        /// 현재 줌을 유지한 채 해당 좌표를 가려지지 않는 영역의 중심으로 이동한다.
        case position(IndoorMapCoordinate)
        /// 같은 층의 서가 후보들을 함께 볼 수 있도록 도형 전체에 맞춘다.
        case features([IndoorMapElement.ID])
    }
    let id: Int
    let target: Target
}
