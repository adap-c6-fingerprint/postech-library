import CoreLocation
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct IndoorLocationAuthorizationMonitorTests {
    private actor ServicesProbe {
        private(set) var calls = 0
        func read() -> Bool { calls += 1; return true }
    }

    private actor ServicesGate {
        private let started: AsyncStream<Int>.Continuation
        private var nextID = 0
        private var pending: [Int: CheckedContinuation<Bool, Never>] = [:]

        init(started: AsyncStream<Int>.Continuation) { self.started = started }

        func read() async -> Bool {
            let id = nextID
            nextID += 1
            return await withCheckedContinuation { continuation in
                pending[id] = continuation
                started.yield(id)
            }
        }

        func resolve(_ id: Int, enabled: Bool) {
            pending.removeValue(forKey: id)?.resume(returning: enabled)
        }
    }

    @Test("MainActor에서 호출해도 동기 시스템 조회는 메인 스레드 밖에서 실행한다")
    func queriesServicesOutsideMainThread() async {
        let offMainThread = await IndoorLocationServices.queryEnabled { !Thread.isMainThread }
        #expect(offMainThread)
    }

    @Test("권한·정확도 콜백을 캐시하고 전역 서비스 조회와 중복 이벤트를 피한다")
    func cachesCallbackStates() async {
        let probe = ServicesProbe()
        var events: [IndoorLocationAuthorization] = []
        let monitor = IndoorLocationAuthorizationMonitor(servicesEnabled: { await probe.read() }) { events.append($0) }
        monitor.update(status: .notDetermined, precise: false)
        monitor.update(status: .authorizedWhenInUse, precise: true)
        monitor.update(status: .authorizedAlways, precise: true)
        monitor.update(status: .authorizedAlways, precise: false)
        monitor.update(status: .restricted, precise: false)
        monitor.update(status: .notDetermined, precise: false)
        #expect(events == [.authorized(precise: true), .authorized(precise: false), .restricted, .notDetermined])
        #expect(monitor.authorization == .notDetermined)
        #expect(await probe.calls == 0)
    }

    @Test("앱 권한 거부와 기기 전체 위치 서비스 OFF를 구분한다", arguments: [true, false])
    func distinguishesServiceDisabled(_ enabled: Bool) async {
        var events: [IndoorLocationAuthorization] = []
        let monitor = IndoorLocationAuthorizationMonitor(servicesEnabled: { enabled }) { events.append($0) }
        let task = monitor.update(status: .denied, precise: false)
        // 느린 조회 중에도 이미 허용된 것처럼 위치 업데이트를 계속하지 않는다.
        #expect(monitor.authorization == .denied)
        await task?.value
        #expect(monitor.authorization == (enabled ? .denied : .servicesDisabled))
        #expect(events == (enabled ? [.denied] : [.denied, .servicesDisabled]))
    }

    @Test("권한 철회는 즉시 전달하며 이전 서비스 조회가 새 권한을 덮어쓰지 못한다",
          arguments: [CLAuthorizationStatus.authorizedWhenInUse, .restricted, .notDetermined])
    func ignoresOldServiceResult(_ status: CLAuthorizationStatus) async throws {
        let started = AsyncStream<Int>.makeStream()
        let gate = ServicesGate(started: started.continuation)
        var events: [IndoorLocationAuthorization] = []
        let monitor = IndoorLocationAuthorizationMonitor(servicesEnabled: { await gate.read() }) { events.append($0) }
        monitor.update(status: .authorizedWhenInUse, precise: true)
        let oldTask = monitor.update(status: .denied, precise: false)
        #expect(events == [.authorized(precise: true), .denied])
        var iterator = started.stream.makeAsyncIterator()
        let requestID = try #require(await iterator.next())
        monitor.update(status: status, precise: false)
        let expected = monitor.authorization
        await gate.resolve(requestID, enabled: false)
        await oldTask?.value
        #expect(monitor.authorization == expected)
        #expect(events.last == expected)
        #expect(!events.contains(.servicesDisabled))
    }

    @Test("같은 denied 상태의 조회도 가장 최신 결과만 반영한다")
    func newestServiceQueryWins() async throws {
        let started = AsyncStream<Int>.makeStream()
        let gate = ServicesGate(started: started.continuation)
        let monitor = IndoorLocationAuthorizationMonitor(servicesEnabled: { await gate.read() }, onChange: { _ in })
        var iterator = started.stream.makeAsyncIterator()
        let first = monitor.update(status: .denied, precise: false)
        let firstID = try #require(await iterator.next())
        let second = monitor.update(status: .denied, precise: false)
        let secondID = try #require(await iterator.next())
        await gate.resolve(secondID, enabled: true)
        await second?.value
        await gate.resolve(firstID, enabled: false)
        await first?.value
        #expect(monitor.authorization == .denied)
    }
}
