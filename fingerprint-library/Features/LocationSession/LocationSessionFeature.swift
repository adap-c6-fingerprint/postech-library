// 앱 활성 수명에 맞춰 위치·기압 이벤트를 한 곳에서 구독하고 추정 층을 공유한다.
import ComposableArchitecture
import Foundation

@Reducer
struct LocationSessionFeature {
    @ObservableState
    struct State: Equatable {
        var isActive = false
        var isBarometerActive = false
        var floorEstimator = FloorEstimator()
        var atriumZone: AtriumZone?
        @Shared(.indoorLocation) var location
    }

    enum Action: Equatable {
        case started
        case sceneActiveChanged(Bool)
        case locationEvent(IndoorLocationEvent)
        case atriumZoneLoaded(AtriumZone)
        case barometerSample(BarometerSample)
    }

    @Dependency(\.indoorLocationClient) var locationClient
    @Dependency(\.indoorMapClient) var mapClient
    @Dependency(\.barometerClient) var barometerClient

    private nonisolated enum CancelID: Hashable, Sendable {
        case events, atriumZone, barometer
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .started:
                guard !state.isActive else { return .none }
                state.isActive = true
                return start(&state)

            case let .sceneActiveChanged(isActive):
                guard state.isActive != isActive else { return .none }
                state.isActive = isActive
                if isActive { return start(&state) }
                return .merge(
                    .cancel(id: CancelID.events), .cancel(id: CancelID.atriumZone),
                    updateBarometerSubscription(&state)
                )

            case let .atriumZoneLoaded(zone):
                state.atriumZone = zone
                return .none

            case let .barometerSample(sample):
                guard state.isActive, state.isBarometerActive,
                      let meters = FloorEstimator.altitudeMeters(fromKilopascals: sample.kilopascals) else { return .none }
                state.floorEstimator.ingestAltitude(meters: meters, at: sample.timestamp)
                // 기압만으로 GPS 측정 시각을 연장하지 않는다. 다음 위치 이벤트에 추정 층을 넣는다.
                return .none

            case let .locationEvent(event):
                guard case let .position(position) = event, position.source == .sensor else {
                    let wasAuthorized = state.location.authorization.isAuthorized
                    state.$location.withLock { $0.apply(event) }
                    if case .authorization = event {
                        if !wasAuthorized, state.location.authorization.isAuthorized {
                            state.floorEstimator.locationUpdatesDidRestart()
                        }
                        return updateBarometerSubscription(&state)
                    }
                    return .none
                }
                if let current = state.location.position, position.timestamp < current.timestamp { return .none }
                let trust = state.atriumZone?.trust(at: position.coordinate) ?? 1
                state.floorEstimator.ingestFloor(level: position.floorOrdinal, trust: trust, at: position.timestamp)
                let estimate = state.floorEstimator.estimate(at: position.timestamp)
                state.$location.withLock { $0.apply(.position(position.replacingFloor(estimate.ordinal))) }
                return .none
            }
        }
    }

    private func start(_ state: inout State) -> Effect<Action> {
        state.floorEstimator.locationUpdatesDidRestart()
        return .merge(subscribe(), updateBarometerSubscription(&state),
                      state.atriumZone == nil ? loadAtriumZone() : .none)
    }

    private func loadAtriumZone() -> Effect<Action> {
        .run { [mapClient] send in
            // 읽기에 실패하면 중앙 공간 가중치 없이 층 보정을 계속한다.
            guard let map = try? await mapClient.load(), !Task.isCancelled else { return }
            await send(.atriumZoneLoaded(AtriumZone(map: map)))
        }
        .cancellable(id: CancelID.atriumZone, cancelInFlight: true)
    }

    private func updateBarometerSubscription(_ state: inout State) -> Effect<Action> {
        let shouldSubscribe = state.isActive && state.location.authorization.isAuthorized
        guard state.isBarometerActive != shouldSubscribe else { return .none }
        state.isBarometerActive = shouldSubscribe
        guard shouldSubscribe else { return .cancel(id: CancelID.barometer) }
        return .run { send in
            for await sample in await barometerClient.samples() {
                guard !Task.isCancelled else { return }
                await send(.barometerSample(sample))
            }
        }
        .cancellable(id: CancelID.barometer, cancelInFlight: true)
    }

    private func subscribe() -> Effect<Action> {
        .run { send in
            for await event in await locationClient.events() {
                guard !Task.isCancelled else { return }
                await send(.locationEvent(event))
            }
        }
        .cancellable(id: CancelID.events, cancelInFlight: true)
    }
}
