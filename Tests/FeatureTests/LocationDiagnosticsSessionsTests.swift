import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

/// 마이페이지의 위치 측정 기록(실험 브랜치 전용)
@MainActor
struct LocationDiagnosticsSessionsTests {
    nonisolated static func session(_ id: String) -> LocationDiagnosticsSessionInfo {
        .init(id: id, folderURL: URL(filePath: "/dev/null"), meta: nil, summary: nil, fileURLs: [])
    }

    @Test func 측정_모드가_꺼져_있으면_마이페이지에서_기록_목록을_열지_않는다() async {
        let store = TestStore(initialState: MyPageFeature.State()) { MyPageFeature() }
        await store.send(.diagnosticsSessionsRowTapped)
        #expect(store.state.diagnosticsSessions == nil)
    }

    @Test func 측정_모드가_켜져_있으면_마이페이지에서_기록_목록을_연다() async {
        let store = TestStore(initialState: MyPageFeature.State()) { MyPageFeature() }
        store.exhaustivity = .off
        store.state.$isLocationDiagnosticsMode.withLock { $0 = true }
        await store.send(.diagnosticsSessionsRowTapped)
        #expect(store.state.diagnosticsSessions != nil)
    }

    @Test func 기록_목록을_불러오고_삭제한다() async {
        let deleted = LockIsolated<[String]>([])
        let store = TestStore(initialState: LocationDiagnosticsSessionsFeature.State()) {
            LocationDiagnosticsSessionsFeature()
        } withDependencies: {
            $0.locationDiagnosticsClient.sessions = { [Self.session("b"), Self.session("a")] }
            $0.locationDiagnosticsClient.deleteSession = { id in deleted.withValue { $0.append(id) } }
        }
        await store.send(.task) { $0.isLoading = true }
        await store.receive(.sessionsLoaded([Self.session("b"), Self.session("a")])) {
            $0.isLoading = false
            $0.sessions = [Self.session("b"), Self.session("a")]
        }
        await store.send(.deleteTapped("b")) { $0.sessions = [Self.session("a")] }
        await store.finish()
        #expect(deleted.value == ["b"])
    }
}
