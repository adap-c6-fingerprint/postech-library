import Foundation
import Testing
@testable import fingerprint_library

struct LocationDiagnosticsRecorderTests {
    private func makeRecorder() -> (LocationDiagnosticsRecorder, URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "LocationDiagnosticsRecorderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        return (LocationDiagnosticsRecorder(rootURL: root), root)
    }

    private func meta(_ startedAt: Date) -> LocationDiagnosticsSessionMeta {
        .init(startedAt: startedAt, posture: .handViewing, includesScreenRecording: false, includesMicrophone: false,
              routePlanID: "plan", bookCount: 1, startsAtEntrance: false, usesManualOrigin: false,
              guidanceThresholds: [:])
    }

    @Test func 종료하면_마지막_줄까지_저장하고_요약과_GeoJSON을_만든다() throws {
        let (recorder, root) = makeRecorder()
        defer { try? FileManager.default.removeItem(at: root) }
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let info = try recorder.start(meta: meta(start))
        #expect(recorder.isRecording)
        for second in 0..<3 {
            recorder.append(.location(.init(
                receivedAt: start.addingTimeInterval(Double(second)), timestamp: start.addingTimeInterval(Double(second)),
                latitude: 36 + Double(second) / 111_195, longitude: 129, horizontalAccuracy: 4, floorLevel: 2)))
        }
        recorder.append(.marker(.init(at: start.addingTimeInterval(1), kind: .jump)))

        let finished = try #require(recorder.finish())
        #expect(!recorder.isRecording)
        #expect(finished.id == info.id)
        #expect(finished.meta?.endedAt != nil)
        #expect(finished.summary?.locationCount == 3)
        #expect(finished.summary?.jumpMarkerCount == 1)
        let names = Set(finished.fileURLs.map(\.lastPathComponent))
        #expect(names == ["session.jsonl", "summary.json", "meta.json", "track.geojson"])

        let records = LocationDiagnosticsRecorder.readRecords(in: finished.folderURL)
        guard case let .event(first)? = records.first, case let .event(last)? = records.last else {
            Issue.record("시작·종료 이벤트가 없어요")
            return
        }
        #expect(first.name == "session_started")
        #expect(last.name == "session_finished")
    }

    @Test func 기록하지_않을_때는_아무것도_쓰지_않고_중단된_세션은_목록에서_요약을_복구한다() throws {
        let (recorder, root) = makeRecorder()
        defer { try? FileManager.default.removeItem(at: root) }
        recorder.append(.marker(.init(at: Date(), kind: .jump)))
        #expect(recorder.sessions().isEmpty)

        _ = try recorder.start(meta: meta(Date(timeIntervalSinceReferenceDate: 2_000)))
        recorder.flush()
        // 앱이 종료돼 finish 없이 남은 세션을 새 Recorder가 목록으로 읽는다.
        let restarted = LocationDiagnosticsRecorder(rootURL: root)
        let sessions = restarted.sessions()
        #expect(sessions.count == 1)
        #expect(sessions.first?.summary != nil)
        _ = recorder.finish()
    }
}
