//
//  IndoorLocationSnapshot.swift
//  fingerprint-library
//

import Foundation

/// 앱이 활성인 동안 하나의 위치 세션이 받은 실내 위치 상태.
///
/// 위치 이벤트를 받을 때마다 갱신하고, 지도·길안내는 이 값의 변화를 이벤트로 되돌려 처리한다.
/// 중간 위치를 놓쳐도 최신 권한·위치·수신 상태가 남으므로 화면이 어긋나지 않는다.
nonisolated struct IndoorLocationSnapshot: Equatable, Sendable {
    nonisolated enum Availability: Equatable, Sendable {
        case available
        /// 위치 재수신을 기다리는 중. 완료된 경로 미리보기는 유지한다.
        case temporarilyUnavailable(String)
        case unavailable(String)
    }

    var authorization: IndoorLocationAuthorization = .notDetermined
    /// 마지막으로 받은 위치. 수신이 끊기거나 권한이 없으면 nil이다. 최신성은 받는 쪽이 시각으로 판단한다.
    var position: IndoorPosition?
    var availability: Availability = .available

    init() {}

    mutating func apply(_ event: IndoorLocationEvent) {
        switch event {
        case let .authorization(authorization):
            self.authorization = authorization
            if !authorization.isAuthorized { position = nil }
        case let .position(position):
            if let current = self.position, position.timestamp < current.timestamp { return }
            self.position = position
            availability = .available
        case let .temporarilyUnavailable(message):
            position = nil
            availability = .temporarilyUnavailable(message)
        case let .unavailable(message):
            position = nil
            availability = .unavailable(message)
        }
    }

    /// 이전 상태에서 바뀐 부분을 위치 이벤트로 돌려준다. 처음 받는 쪽(previous == nil)에는 현재 상태 전체를 알린다.
    func events(since previous: Self?) -> [IndoorLocationEvent] {
        var events: [IndoorLocationEvent] = []
        if previous?.authorization != authorization {
            events.append(.authorization(authorization))
        }
        if previous?.availability != availability {
            switch availability {
            case .available: break
            case let .temporarilyUnavailable(message): events.append(.temporarilyUnavailable(message))
            case let .unavailable(message): events.append(.unavailable(message))
            }
        }
        if let position, previous?.position != position {
            events.append(.position(position))
        }
        return events
    }
}
