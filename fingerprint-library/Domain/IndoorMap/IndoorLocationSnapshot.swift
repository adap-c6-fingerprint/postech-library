//
//  IndoorLocationSnapshot.swift
//  fingerprint-library
//

import Foundation

nonisolated struct IndoorLocationSnapshot: Equatable, Sendable {
    nonisolated enum Availability: Equatable, Sendable {
        case available
        case temporarilyUnavailable(String)
        case unavailable(String)
    }

    var authorization: IndoorLocationAuthorization = .notDetermined
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
