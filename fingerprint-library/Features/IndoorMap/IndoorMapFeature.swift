import Combine
import ComposableArchitecture
import Foundation

/// 지도 로딩·층 조회·위치 수신·단일 서가 경로 요청을 연결하는 TCA 기능.
///
/// 파일과 위치 시스템은 Clients를 통해 사용하고, MapKit 객체는 View에서 관리한다.
/// 지도와 navigation 로딩 상태를 분리해 노드 자료가 준비되지 않아도 지도를 표시한다.
@Reducer
struct IndoorMapFeature {
    /// 위치를 모를 때 처음 보여 줄 층. ordinal 2는 화면 표기로 3F다.
    static let defaultFloorOrdinal = 2

    /// 지도 화면에 필요한 값 상태. 표시 중인 층과 실제 위치의 층은 서로 다를 수 있다.
    @ObservableState
    struct State: Equatable {
        /// 이 Store의 진행 중 작업을 다른 Store와 구분하는 값.
        ///
        /// 홈 지도와 경로 미리보기가 같은 Feature로 서로 다른 Store를 만든다. 취소 ID가 같으면
        /// 한쪽 화면이 닫히거나 새로 뜰 때 다른 쪽의 지도·서가·위치 작업까지 취소된다.
        /// 같은 지도 기능이 여러 화면에 있을 때 취소 ID를 나누는 값. uuid 의존성으로 만든다.
        let instanceID: UUID = { @Dependency(\.uuid) var uuid; return uuid() }()
        var homeAnnotations = HomeMapAnnotationsFeature.State()
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
        /// 실제 위치의 층을 아직 한 번도 반영하지 않았는지. 기본 층에서 한 번만 자동으로 옮기기 위해 쓴다.
        var awaitsPositionFloor = true
        /// 실내 측위가 마지막으로 알려 준 층. 신호가 잠깐 끊겨도 지우지 않아, 실제로 층이 바뀔 때만 지도를 옮긴다.
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
                // 위치를 알면 그 층을, 모르면 3F를 먼저 보여 준다.
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
                    // 실내 측위가 층 이동을 알리면 지도도 그 층으로 옮긴다.
                    // 같은 층에 머무는 동안에는 사용자가 고른 조회 층을 지킨다.
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
                    // 권한을 거절한 사용자에게 홈 지도 위 경고 문구를 띄우지 않는다.
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
                // 직접 고른 층을 위치 수신이 덮어쓰지 않게 한다.
                state.awaitsPositionFloor = false
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

    /// 진행 중인 경로 탐색과 계단 확인만 취소하고 이미 계산한 미리보기는 보존한다.
    /// 일시적인 위치 수신 중단은 경로 자체를 무효화하는 사유와 구분한다.
    private func cancelRouteSearch(_ state: inout State) -> Effect<Action> {
        guard state.isRouting || state.requiresStairConfirmation else { return .none }
        state.routeRequestID += 1
        state.isRouting = false
        state.requiresStairConfirmation = false
        return .cancel(id: CancelID(state.instanceID, .route))
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
        return .cancel(id: CancelID(state.instanceID, .route))
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

    /// 지도가 없거나 이전 로딩이 실패한 경우 도면 로딩을 시작하고 성공·실패 Action으로 전달한다.
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

    /// 서가 표시 자료만 갱신한다. 실패해도 지도·층 선택·길찾기 로딩을 유지한다.
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

    /// LocationSessionFeature가 쓰는 공유 위치 상태를 화면 수명 동안 읽고, 바뀐 부분을 위치 이벤트로 처리한다.
    /// 위치 센서 스트림은 새로 열지 않는다. 다시 읽기 시작하면 이전 구독을 취소한다.
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
        }.cancellable(id: CancelID(state.instanceID, .navigation), cancelInFlight: true)
    }

    /// 호출부에서 수락한 현재 위치로 조회 층과 카메라를 이동하고 한 번의 포커싱 요청을 마친다.
    private func recenter(_ state: inout State, position: IndoorPosition) {
        if let ordinal = position.floorOrdinal,
           let floor = state.map?.floors.first(where: { $0.ordinal == ordinal }) {
            if state.selectedFloorID != floor.id { state.selectedShelfKey = nil }
            state.selectedFloorID = floor.id
            state.awaitsPositionFloor = false
        }
        // 현재 위치 버튼은 북쪽을 위로 돌리고, 주변 서가 번호가 보이는 배율로 확대한다.
        state.requestCamera(.position(position.coordinate, revealsShelfNumbers: true))
        state.wantsRecenter = false
        state.locationMessage = nil
    }
}
