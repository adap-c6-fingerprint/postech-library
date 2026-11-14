import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct RouteStartPolicyTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000)
    private let policy = RouteStartPolicy()

    private func position(latitude: Double = 36.0127633, longitude: Double = 129.3251348,
                          floor: Int? = 2, age: TimeInterval = 0) -> IndoorPosition {
        .init(coordinate: .init(latitude: latitude, longitude: longitude), floorOrdinal: floor,
              horizontalAccuracy: 5, timestamp: now.addingTimeInterval(-age), source: .sensor)
    }

    @Test func 번들_외곽선과_주출입구의_층을_읽는다() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        #expect(map.groundFootprint != nil)
        #expect(map.principalEntrances.count == 7)
        #expect(map.principalEntrances.filter { $0.floorOrdinal == 0 }.count == 4)
        #expect(map.principalEntrances.filter { $0.floorOrdinal == 4 }.count == 3)
    }

    @Test func 내부는_현재_층을_쓰고_층을_모르면_출발점을_직접_선택한다() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let inside = position()
        #expect(policy.decide(position: inside, isAuthorized: true, map: map, now: now) == .current(inside))
        for floor in [Int?.none, 99] {
            let decision = policy.decide(position: position(floor: floor), isAuthorized: true, map: map, now: now)
            #expect(decision == .needsOrigin(.unknownFloor))
            #expect(decision.startPosition == nil)
            #expect(decision.notice != nil)
        }
    }

    @Test func 바로_밖에서는_다른_건물의_층을_무시하고_주출입구에서_출발한다() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        for floor in [Int?.none, 2] {
            let outside = position(latitude: 36.0129329, longitude: 129.3256179, floor: floor)
            let decision = policy.decide(position: outside, isAuthorized: true, map: map, now: now)
            guard case let .entrance(start, reason) = decision else {
                Issue.record("바로 밖은 주출입구 기준이어야 합니다: \(decision)")
                continue
            }
            #expect(reason == .outside)
            #expect(start.floorOrdinal == 0)
            #expect(start.source == .manual)
        }
        let far = position(latitude: 36.0130858, longitude: 129.3259576)
        #expect(policy.decide(position: far, isAuthorized: true, map: map, now: now) == .needsOrigin(.farOutside))

    }

    @Test func 권한과_사용할_위치가_없을_때를_구분한다() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        #expect(policy.decide(position: position(), isAuthorized: false, map: map, now: now)
                == .needsOrigin(.notAuthorized))
        #expect(policy.decide(position: nil, isAuthorized: true, map: map, now: now) == .locating)
        #expect(policy.decide(position: position(age: 60), isAuthorized: true, map: map, now: now) == .locating)
        var noEntrances = map.features
        noEntrances.removeAll { $0.kind == .opening }
        let mapWithoutEntrances = IndoorMap(formatVersion: map.formatVersion, venue: map.venue,
            floors: map.floors, features: noEntrances, diagnostics: map.diagnostics)
        #expect(policy.decide(position: position(latitude: 36.0129329, longitude: 129.3256179, floor: nil), isAuthorized: true,
                              map: mapWithoutEntrances, now: now) == .needsOrigin(.noEntrance))
    }

    @Test func 외부의_층_정보로_내부로_오인하지_않는다() {
        let scale = 111_320.0
        let outline = IndoorMapGeometry.polygon([[
            .init(latitude: 0, longitude: 0), .init(latitude: 0, longitude: 100 / scale),
            .init(latitude: 100 / scale, longitude: 100 / scale), .init(latitude: 100 / scale, longitude: 0),
            .init(latitude: 0, longitude: 0)
        ]])
        func outside(_ distance: Double, floor: Int? = nil) -> IndoorPosition {
            let latitude = 50 / scale
            return position(latitude: latitude, longitude: -distance / (scale * cos(latitude * .pi / 180)), floor: floor)
        }
        #expect(abs(outline.distanceToBoundaryMeters(from: outside(10).coordinate) - 10) < 0.001)
        #expect(policy.zone(of: outside(2.5, floor: 2), outline: outline) == .nearOutside)
        #expect(policy.zone(of: outside(2.5), outline: outline) == .nearOutside)
        #expect(policy.zone(of: outside(1.5), outline: outline) == .nearOutside)
        #expect(policy.zone(of: outside(19.99), outline: outline) == .nearOutside)
        #expect(policy.zone(of: outside(20), outline: outline) == .nearOutside)
        #expect(policy.zone(of: outside(20.01), outline: outline) == .farOutside)
        #expect(policy.zone(of: outside(21), outline: outline) == .farOutside)
        #expect(policy.zone(of: outside(22.5), outline: outline) == .farOutside)
    }

    @Test func 모든_주출입구에서_서가까지_연결되고_멀리_떨어진_출발점은_거절한다() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        let floor = try #require(map.floors.first { $0.ordinal == 2 })
        let shelf = try #require(labels.first { $0.floorID == floor.id && $0.realNumber == "343" && $0.side == .a })
        let stops = [RouteCandidateStop(book: makeBook(1), holdings: [], candidateShelves: [shelf])]
        let reference = try await RoutePlanningLoader().load(on: map, labels: labels, start: position(), stops: stops)
        let edge = try #require(reference.graph.edges.first { edge in
            reference.graph.nodes.contains { $0.id == edge.fromNodeID && $0.level == 2 }
                && reference.graph.nodes.contains { $0.id == edge.toNodeID && $0.level == 2 }
        })
        let a = try #require(edge.coordinates.first), b = try #require(edge.coordinates.last)
        let between = position(latitude: (a.latitude + b.latitude) / 2, longitude: (a.longitude + b.longitude) / 2)
        let fromBetween = try await RoutePlanningLoader().load(on: map, labels: labels, start: between, stops: stops)
        let nearest = try #require(reference.graph.nodes.filter { $0.level == 2 }.min {
            RoutingGeometry.distanceMeters(from: $0.coordinate, to: between.coordinate)
                < RoutingGeometry.distanceMeters(from: $1.coordinate, to: between.coordinate)
        })
        let selected = try #require(reference.graph.nodes.first { $0.id == fromBetween.route.nodeIDs.first })
        #expect(selected.level == 2)
        #expect(abs(RoutingGeometry.distanceMeters(from: selected.coordinate, to: between.coordinate)
            - RoutingGeometry.distanceMeters(from: nearest.coordinate, to: between.coordinate)) < 0.001)
        #expect(fromBetween.route.start.routeCoordinate == selected.coordinate)
        for entrance in map.principalEntrances {
            let start = IndoorPosition(coordinate: entrance.coordinate, floorOrdinal: entrance.floorOrdinal,
                horizontalAccuracy: nil, timestamp: now, source: .manual)
            let plan = try await RoutePlanningLoader().load(on: map, labels: labels, start: start, stops: stops)
            #expect(!plan.legs.isEmpty)
            #expect(plan.route.start.distanceToGraphMeters < 25)
        }
        do {
            _ = try await RoutePlanningLoader().load(on: map, labels: labels,
                start: position(latitude: 36.0147633), stops: stops)
            Issue.record("50m를 넘는 노드 대체는 실패해야 합니다.")
        } catch {
            #expect(error as? IndoorRoutingError == .farFromGraph)
        }
    }
}
