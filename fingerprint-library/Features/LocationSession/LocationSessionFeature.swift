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
        @Shared(.indoorLocation) var location
    }

    enum Action: Equatable {
        /// 앱 루트 화면이 뜰 때 한 번 보낸다.
        case started
        case sceneActiveChanged(Bool)
        case locationEvent(IndoorLocationEvent)
    }

    @Dependency(\.indoorLocationClient) var locationClient

    private nonisolated enum CancelID: Hashable, Sendable {
        case events
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .started:
                guard !state.isActive else { return .none }
                state.isActive = true
                return subscribe()

            case let .sceneActiveChanged(isActive):
                guard state.isActive != isActive else { return .none }
                state.isActive = isActive
                // 비활성이 되면 센서 구독을 멈춰 배터리를 아낀다. 다시 활성이 되면 새로 구독한다.
                return isActive ? subscribe() : .cancel(id: CancelID.events)

            case let .locationEvent(event):
                state.$location.withLock { $0.apply(event) }
                return .none
            }
        }
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
