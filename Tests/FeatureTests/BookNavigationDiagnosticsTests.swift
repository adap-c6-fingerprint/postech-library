import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookNavigationDiagnosticsTests {
    static let now = Date(timeIntervalSinceReferenceDate: 0)
    static let startCoordinate = IndoorMapCoordinate(latitude: 36.0127633, longitude: 129.3251348)

    private static func makePlan() async throws -> RoutePlan {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        let thirdFloor = try #require(map.floors.first { $0.ordinal == 2 })
        let shelf = try #require(labels.first { $0.floorID == thirdFloor.id && $0.realNumber == "343" && $0.side == .a })
        let start = IndoorPosition(coordinate: startCoordinate, floorOrdinal: 2, horizontalAccuracy: 3,
                                   timestamp: now, source: .manual)
        return try await RoutePlanningLoader().load(
            on: map, labels: labels, start: start,
            stops: [RouteCandidateStop(book: makeBook(0), holdings: [], candidateShelves: [shelf])])
    }

    private static func makeStore(
        records: LockIsolated<[LocationDiagnosticsRecord]>, finishCount: LockIsolated<Int>
    ) async throws -> TestStoreOf<BookNavigationFeature> {
        var state = BookNavigationFeature.State(routePlan: try await makePlan())
        state.isActive = true
        state.authorization = .authorized(precise: true)
        let store = TestStore(initialState: state) { BookNavigationFeature() } withDependencies: {
            $0.date.now = now
            $0.continuousClock = TestClock()
            $0.analyticsClient = .testValue
            $0.locationDiagnosticsClient.record = { record in records.withValue { $0.append(record) } }
            $0.locationDiagnosticsClient.finishSession = {
                finishCount.withValue { $0 += 1 }
                return nil
            }
        }
        store.exhaustivity = .off
        return store
    }

    private func position(accuracy: Double, after seconds: Double = 0) -> IndoorPosition {
        IndoorPosition(coordinate: Self.startCoordinate, floorOrdinal: 2, horizontalAccuracy: accuracy,
                       timestamp: Self.now.addingTimeInterval(seconds), source: .sensor)
    }

    @Test func 기록을_켜지_않으면_위치를_받아도_진단을_남기지_않는다() async throws {
        let records = LockIsolated<[LocationDiagnosticsRecord]>([])
        let finishCount = LockIsolated(0)
        let store = try await Self.makeStore(records: records, finishCount: finishCount)

        await store.send(.locationEvent(subscriptionID: 0, .position(position(accuracy: 3))))
        await store.send(.disappeared)

        #expect(records.value.isEmpty)
        #expect(finishCount.value == 0)
        #expect(store.state.diagnostics == .init())
    }

    @Test func 기록_중에는_경로와_위치별_판정을_남기고_화면을_닫으면_기록을_끝낸다() async throws {
        let records = LockIsolated<[LocationDiagnosticsRecord]>([])
        let finishCount = LockIsolated(0)
        let store = try await Self.makeStore(records: records, finishCount: finishCount)
        let info = LocationDiagnosticsSessionInfo(id: "test", folderURL: URL(filePath: "/dev/null"),
                                                  meta: nil, summary: nil, fileURLs: [])

        await store.send(.diagnostics(.sessionStarted(info)))
        #expect(store.state.diagnostics.isRecording)
        #expect(records.value.contains { if case .route = $0 { true } else { false } })

        await store.send(.locationEvent(subscriptionID: 0, .position(position(accuracy: 3))))
        await store.send(.locationEvent(subscriptionID: 0, .position(position(accuracy: 20, after: 1))))
        let guidance = records.value.compactMap { record -> LocationDiagnosticsRecord.GuidanceSample? in
            if case let .guidance(sample) = record { sample } else { nil }
        }
        #expect(guidance.count == 2)
        #expect(guidance.last?.quality == "inaccurate")
        #expect(store.state.diagnostics.lastQuality == "inaccurate")

        await store.send(.diagnostics(.jumpMarkerTapped))
        #expect(records.value.contains { if case let .marker(marker) = $0 { marker.kind == .jump } else { false } })

        await store.send(.disappeared)
        await store.receive(.diagnostics(.sessionFinished(nil)))
        #expect(finishCount.value == 1)
        #expect(!store.state.diagnostics.isRecording)
    }

    @Test func 기준점은_지도_중앙을_받은_뒤에만_남기고_카메라_따라가기를_되돌린다() async throws {
        let records = LockIsolated<[LocationDiagnosticsRecord]>([])
        let store = try await Self.makeStore(records: records, finishCount: LockIsolated(0))
        let info = LocationDiagnosticsSessionInfo(id: "test", folderURL: URL(filePath: "/dev/null"),
                                                  meta: nil, summary: nil, fileURLs: [])
        await store.send(.diagnostics(.sessionStarted(info)))

        await store.send(.diagnostics(.checkpointModeTapped))
        #expect(store.state.diagnostics.isPlacingCheckpoint)
        #expect(!store.state.followsNavigationCamera)
        await store.send(.diagnostics(.checkpointConfirmed))
        #expect(store.state.diagnostics.checkpointCount == 0)

        await store.send(.diagnostics(.checkpointCenterChanged(Self.startCoordinate)))
        await store.send(.diagnostics(.checkpointConfirmed))
        #expect(store.state.diagnostics.checkpointCount == 1)
        #expect(!store.state.diagnostics.isPlacingCheckpoint)
        #expect(store.state.followsNavigationCamera)
        let checkpoint = records.value.compactMap { record -> LocationDiagnosticsRecord.Marker? in
            if case let .marker(marker) = record, marker.kind == .checkpoint { marker } else { nil }
        }
        #expect(checkpoint.first?.coordinate == Self.startCoordinate)
    }
}
