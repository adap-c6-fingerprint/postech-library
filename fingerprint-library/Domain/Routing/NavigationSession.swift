//
//  NavigationSession.swift
//  fingerprint-library
//

import Foundation

struct NavigationSession: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case cancelled
        case completed
    }

    let routePlan: RoutePlan
    private(set) var currentStopIndex = 0
    private(set) var reroutedLegs: [Int: IndoorRoute] = [:]
    private(set) var arrivedStopIndices: Set<Int> = []
    private(set) var outcome: Outcome?

    init(routePlan: RoutePlan) {
        self.routePlan = routePlan
    }

    var isActive: Bool { outcome == nil }

    var currentStop: RouteStop? {
        routePlan.stops.indices.contains(currentStopIndex) ? routePlan.stops[currentStopIndex] : nil
    }

    var currentLeg: IndoorRoute? { leg(at: currentStopIndex) }

    var hasNextStop: Bool { currentStopIndex >= 0 && currentStopIndex < routePlan.stops.count - 1 }

    var hasPreviousStop: Bool { currentStopIndex > 0 && routePlan.stops.indices.contains(currentStopIndex - 1) }

    func leg(at index: Int) -> IndoorRoute? {
        reroutedLegs[index] ?? (routePlan.legs.indices.contains(index) ? routePlan.legs[index] : nil)
    }

    @discardableResult
    mutating func advance() -> Bool {
        guard isActive, hasNextStop else { return false }
        currentStopIndex += 1
        return true
    }

    @discardableResult
    mutating func move(to index: Int) -> Bool {
        guard isActive, routePlan.stops.indices.contains(index) else { return false }
        currentStopIndex = index
        arrivedStopIndices.remove(index)
        return true
    }

    @discardableResult
    mutating func replaceLeg(at index: Int, with route: IndoorRoute) -> Bool {
        guard routePlan.legs.indices.contains(index),
              route.destination == routePlan.legs[index].destination else { return false }
        reroutedLegs[index] = route
        return true
    }

    @discardableResult
    mutating func markArrived() -> Bool {
        arrivedStopIndices.insert(currentStopIndex).inserted
    }

    mutating func finish(_ outcome: Outcome) {
        guard isActive else { return }
        self.outcome = outcome
    }
}
