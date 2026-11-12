//
//  NavigationSession.swift
//  fingerprint-library
//

import Foundation

/// 길안내 진행 상태. 확정한 RoutePlan을 따라 현재 방문지, 구간별 경로, 도착 확인, 종료 결과를 관리한다.
///
/// 위치를 경로에 투영하고 안내 문구를 만드는 일은 GuidanceEngine이 맡는다.
/// 이 값은 어느 방문지를 어떤 경로로 안내 중인지와, 안내가 끝났는지만 정한다.
struct NavigationSession: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case cancelled
        case completed
    }

    let routePlan: RoutePlan
    private(set) var currentStopIndex = 0
    /// 현재 위치에서 다시 계산한 구간 경로. 없으면 계획의 구간 경로를 쓴다.
    private(set) var reroutedLegs: [Int: IndoorRoute] = [:]
    /// 도착을 확인한 방문지. 같은 방문지에서 도착 화면을 다시 띄우지 않는다.
    private(set) var arrivedStopIndices: Set<Int> = []
    /// 안내를 마친 결과. nil이면 안내 중이다.
    private(set) var outcome: Outcome?

    init(routePlan: RoutePlan) {
        self.routePlan = routePlan
    }

    var isActive: Bool { outcome == nil }

    var currentStop: RouteStop? {
        routePlan.stops.indices.contains(currentStopIndex) ? routePlan.stops[currentStopIndex] : nil
    }

    /// 지금 안내 중인 구간의 경로.
    var currentLeg: IndoorRoute? { leg(at: currentStopIndex) }

    var hasNextStop: Bool { currentStopIndex >= 0 && currentStopIndex < routePlan.stops.count - 1 }

    var hasPreviousStop: Bool { currentStopIndex > 0 && routePlan.stops.indices.contains(currentStopIndex - 1) }

    func leg(at index: Int) -> IndoorRoute? {
        reroutedLegs[index] ?? (routePlan.legs.indices.contains(index) ? routePlan.legs[index] : nil)
    }

    /// 다음 방문지로 넘어간다. 남은 방문 순서와 선택한 서가는 바꾸지 않는다.
    @discardableResult
    mutating func advance() -> Bool {
        guard isActive, hasNextStop else { return false }
        currentStopIndex += 1
        return true
    }

    /// 지정한 방문지로 돌아간다. 돌아간 방문지에서는 도착을 다시 확인한다.
    @discardableResult
    mutating func move(to index: Int) -> Bool {
        guard isActive, routePlan.stops.indices.contains(index) else { return false }
        currentStopIndex = index
        arrivedStopIndices.remove(index)
        return true
    }

    /// 구간 경로를 다시 계산한 경로로 바꾼다. 계획과 다른 서가로 가는 경로는 받지 않는다.
    @discardableResult
    mutating func replaceLeg(at index: Int, with route: IndoorRoute) -> Bool {
        guard routePlan.legs.indices.contains(index),
              route.destination == routePlan.legs[index].destination else { return false }
        reroutedLegs[index] = route
        return true
    }

    /// 현재 방문지 도착을 기록한다. 처음 기록하면 true를 돌려준다.
    @discardableResult
    mutating func markArrived() -> Bool {
        arrivedStopIndices.insert(currentStopIndex).inserted
    }

    /// 안내를 마친다. 이미 마친 안내의 결과는 바꾸지 않는다.
    mutating func finish(_ outcome: Outcome) {
        guard isActive else { return }
        self.outcome = outcome
    }
}
