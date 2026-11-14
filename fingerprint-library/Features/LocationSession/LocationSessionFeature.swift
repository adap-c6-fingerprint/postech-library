//
//  LocationSessionFeature.swift
//  fingerprint-library
//
//  앱 활성 수명에 맞춰 위치 이벤트를 한 곳에서 구독한다.
//  홈 지도·경로 미리보기·길안내는 위치 스트림을 새로 열지 않고 @Shared(.indoorLocation)를 읽는다.
//

import ComposableArchitecture
import Foundation

@Reducer
struct LocationSessionFeature {
    @ObservableState
    struct State: Equatable {
        var isActive = false
        var isBarometerActive = false
        var floorEstimator = FloorEstimator()
        @Shared(.indoorLocation) var location
    }

    enum Action: Equatable {
        case started
        case sceneActiveChanged(Bool)
        case locationEvent(IndoorLocationEvent)
        case barometerSample(BarometerSample)
    }

    @Dependency(\.indoorLocationClient) var locationClient
    @Dependency(\.barometerClient) var barometerClient

    private nonisolated enum CancelID: Hashable, Sendable {
        case events
        case barometer
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .started:
                guard !state.isActive else { return .none }
                state.isActive = true
                state.floorEstimator.locationUpdatesDidRestart()
                return .merge(subscribe(), updateBarometerSubscription(state: &state))

            case let .sceneActiveChanged(isActive):
                guard state.isActive != isActive else { return .none }
                state.isActive = isActive
                if isActive { state.floorEstimator.locationUpdatesDidRestart() }
                return .merge(
                    isActive ? subscribe() : .cancel(id: CancelID.events),
                    updateBarometerSubscription(state: &state)
                )

            case let .locationEvent(event):
                if case let .position(position) = event, position.source == .sensor {
                    state.floorEstimator.ingestFloor(level: position.floorOrdinal, at: position.timestamp)
                    let estimate = state.floorEstimator.estimate(at: position.timestamp)
                    state.$location.withLock { $0.apply(.position(position.replacingFloor(estimate.ordinal))) }
                } else {
                    let wasAuthorized = state.location.authorization.isAuthorized
                    state.$location.withLock { $0.apply(event) }
                    if case .authorization = event {
                        if !wasAuthorized, state.location.authorization.isAuthorized {
                            state.floorEstimator.locationUpdatesDidRestart()
                        }
                        return updateBarometerSubscription(state: &state)
                    }
                }
                return .none

            case let .barometerSample(sample):
                guard state.isActive, state.isBarometerActive else { return .none }
                state.floorEstimator.ingestPressure(kilopascals: sample.kilopascals, at: sample.timestamp)
                // GPS 측정 시각을 연장하지 않는다. 다음 위치 이벤트에 추정 층을 반영한다.
                return .none
            }
        }
    }

    private func updateBarometerSubscription(state: inout State) -> Effect<Action> {
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
