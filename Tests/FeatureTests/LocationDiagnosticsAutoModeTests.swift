import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

/// 검색창 `/test` 측정 모드(실험 브랜치 전용)
@MainActor
struct LocationDiagnosticsAutoModeTests {
    static let now = Date(timeIntervalSinceReferenceDate: 0)

    @Test func 검색창에_test를_입력하면_검색하지_않고_측정_모드를_켜고_끈다() async throws {
        let searchCount = LockIsolated(0)
        let state = withDependencies { $0.uuid = .incrementing } operation: { BookSearchFeature.State() }
        let store = TestStore(initialState: state) { BookSearchFeature() } withDependencies: {
            $0.bookSearchClient.cached = { _ in nil }
            $0.bookSearchClient.search = { _, _ in
                searchCount.withValue { $0 += 1 }
                return []
            }
        }
        store.exhaustivity = .off
        @Shared(.locationDiagnosticsAutoRecord) var isAutoRecording

        await store.send(.queryChanged(" /test "))
        await store.send(.searchButtonTapped)
        #expect(isAutoRecording)
        #expect(store.state.query.isEmpty)
        #expect(store.state.commandNotice?.title == "측정 모드를 켰어요")
        #expect(searchCount.value == 0)

        await store.send(.commandNoticeDismissed)
        #expect(store.state.commandNotice == nil)

        await store.send(.queryChanged("/test"))
        await store.send(.searchButtonTapped)
        #expect(!isAutoRecording)
        #expect(store.state.commandNotice?.title == "측정 모드를 껐어요")
    }

    private static func makePlan() async throws -> RoutePlan {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        let floor = try #require(map.floors.first { $0.ordinal == 2 })
        let shelf = try #require(labels.first { $0.floorID == floor.id && $0.realNumber == "343" && $0.side == .a })
        let start = IndoorPosition(coordinate: .init(latitude: 36.0127633, longitude: 129.3251348), floorOrdinal: 2,
                                   horizontalAccuracy: 3, timestamp: now, source: .manual)
        return try await RoutePlanningLoader().load(
            on: map, labels: labels, start: start,
            stops: [RouteCandidateStop(book: makeBook(0), holdings: [], candidateShelves: [shelf])])
    }

    private static func makeStore(started: LockIsolated<[LocationDiagnosticsSessionMeta]>,
                                  finished: LockIsolated<Int>) async throws -> TestStoreOf<BookNavigationFeature> {
        let plan = try await makePlan()
        let store = TestStore(initialState: BookNavigationFeature.State(routePlan: plan)) {
            BookNavigationFeature()
        } withDependencies: {
            $0.date.now = now
            $0.continuousClock = TestClock()
            $0.analyticsClient = .testValue
            $0.locationDiagnosticsClient.startSession = { meta in
                started.withValue { $0.append(meta) }
                return .init(id: "auto", folderURL: URL(filePath: "/dev/null"), meta: meta, summary: nil, fileURLs: [])
            }
            $0.locationDiagnosticsClient.finishSessionInBackground = { _ in finished.withValue { $0 += 1 } }
        }
        store.exhaustivity = .off
        return store
    }

    @Test func 측정_모드가_켜져_있으면_안내를_열_때_화면_녹화_없이_자동으로_기록하고_닫으면_저장한다() async throws {
        let started = LockIsolated<[LocationDiagnosticsSessionMeta]>([])
        let finished = LockIsolated(0)
        let store = try await Self.makeStore(started: started, finished: finished)
        @Shared(.locationDiagnosticsAutoRecord) var isAutoRecording
        $isAutoRecording.withLock { $0 = true }

        await store.send(.task)
        #expect(store.state.diagnostics.isAutoMode)
        #expect(store.state.diagnostics.isRecording)
        let meta = try #require(started.value.first)
        #expect(meta.isAutomatic == true)
        #expect(!meta.includesScreenRecording)

        await store.send(.disappeared)
        #expect(finished.value == 1)
        #expect(!store.state.diagnostics.isRecording)
    }

    @Test func 측정_모드가_꺼져_있으면_자동으로_기록하지_않는다() async throws {
        let started = LockIsolated<[LocationDiagnosticsSessionMeta]>([])
        let store = try await Self.makeStore(started: started, finished: LockIsolated(0))
        await store.send(.task)
        #expect(!store.state.diagnostics.isAutoMode)
        #expect(started.value.isEmpty)
        await store.skipInFlightEffects()
    }

    @Test func 패널에서_측정_모드를_끄면_지금_기록을_저장하고_다음_안내부터_기록하지_않는다() async throws {
        let started = LockIsolated<[LocationDiagnosticsSessionMeta]>([])
        let store = try await Self.makeStore(started: started, finished: LockIsolated(0))
        @Shared(.locationDiagnosticsAutoRecord) var isAutoRecording
        $isAutoRecording.withLock { $0 = true }
        await store.send(.task)

        await store.send(.diagnostics(.autoModeTurnedOff))
        #expect(!isAutoRecording)
        #expect(!store.state.diagnostics.isAutoMode)
        #expect(!store.state.diagnostics.isRecording)
        await store.skipInFlightEffects()
    }

    @Test func 안내_화면이_사라졌다_다시_나타나도_자동_기록이_이어지고_이전_기록만_닫는다() async throws {
        let started = LockIsolated<[LocationDiagnosticsSessionMeta]>([])
        let finishedIDs = LockIsolated<[String]>([])
        let plan = try await Self.makePlan()
        let store = TestStore(initialState: BookNavigationFeature.State(routePlan: plan)) {
            BookNavigationFeature()
        } withDependencies: {
            $0.date.now = Self.now
            $0.continuousClock = TestClock()
            $0.analyticsClient = .testValue
            $0.locationDiagnosticsClient.startSession = { meta in
                started.withValue { $0.append(meta) }
                return .init(id: "session-\(started.value.count)", folderURL: URL(filePath: "/dev/null"), meta: meta,
                             summary: nil, fileURLs: [])
            }
            $0.locationDiagnosticsClient.finishSessionInBackground = { id in finishedIDs.withValue { $0.append(id) } }
        }
        store.exhaustivity = .off
        @Shared(.locationDiagnosticsAutoRecord) var isAutoRecording
        $isAutoRecording.withLock { $0 = true }

        // fullScreenCover가 화면을 한 번 버렸다가 다시 만드는 순서
        await store.send(.task)
        await store.send(.disappeared)
        await store.send(.task)

        #expect(started.value.count == 2)
        #expect(finishedIDs.value == ["session-1"])
        #expect(store.state.diagnostics.session?.id == "session-2")
        #expect(store.state.diagnostics.isRecording)
        await store.skipInFlightEffects()
    }
}
