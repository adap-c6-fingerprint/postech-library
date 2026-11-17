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
        .init(startedAt: startedAt, posture: .handViewing, includesScreenRecording: false,
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

    /// 안내 화면이 열리며 자동 기록이 같은 초에 두 번 시작되는 경우.
    /// 첫 기록은 짧아서 폴더째 지워지고, 늦게 도착한 첫 기록의 종료 요청이 새 기록을 닫으면 안 된다.
    @Test func 지워진_짧은_자동_기록의_늦은_종료_요청이_같은_초에_시작한_새_기록을_닫지_않는다() throws {
        let (recorder, root) = makeRecorder()
        defer { try? FileManager.default.removeItem(at: root) }
        let startedAt = Date()
        var automatic = meta(startedAt)
        automatic.isAutomatic = true

        let first = try recorder.start(meta: automatic)
        let second = try recorder.start(meta: automatic)

        #expect(second.id != first.id)
        #expect(!FileManager.default.fileExists(atPath: first.folderURL.path()))
        #expect(recorder.finish(sessionID: first.id) == nil)
        #expect(recorder.isRecording)
        #expect(recorder.activeSessionID == second.id)
    }

    @Test func 내보내기는_기록_폴더를_기록_ID_이름의_ZIP_하나로_묶는다() throws {
        let (recorder, root) = makeRecorder()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try recorder.start(meta: meta(Date(timeIntervalSinceReferenceDate: 3_000)))
        let session = try #require(recorder.finish())

        let zipURL = try LocationDiagnosticsArchive(session: session).makeZip(in: root)

        #expect(zipURL.lastPathComponent == "\(session.id).zip")
        let data = try Data(contentsOf: zipURL)
        #expect(data.starts(with: [0x50, 0x4B, 0x03, 0x04]))  // ZIP 로컬 파일 헤더 "PK\u{3}\u{4}"
        // ZIP 목록에는 파일 경로가 그대로 들어 있다. 기록 ID 폴더 아래에 기록 파일이 모두 있어야 한다.
        for name in session.fileURLs.map(\.lastPathComponent) {
            #expect(data.range(of: Data("\(session.id)/\(name)".utf8)) != nil, "\(name)이 ZIP에 없어요")
        }
    }

    @Test func 내보내기는_공유_중일_수_있는_최근_ZIP은_남기고_오래된_ZIP만_정리한다() throws {
        let (recorder, root) = makeRecorder()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try recorder.start(meta: meta(Date(timeIntervalSinceReferenceDate: 4_000)))
        let archive = LocationDiagnosticsArchive(session: try #require(recorder.finish()))
        let exportDirectory = root.appending(path: "exports", directoryHint: .isDirectory)
        let now = Date()

        let first = try archive.makeZip(in: exportDirectory, now: now)
        let second = try archive.makeZip(in: exportDirectory, now: now.addingTimeInterval(60))
        #expect(FileManager.default.fileExists(atPath: first.path()))

        let third = try archive.makeZip(
            in: exportDirectory, now: now.addingTimeInterval(LocationDiagnosticsArchive.staleExportAge + 60))
        #expect(!FileManager.default.fileExists(atPath: first.path()))
        #expect(!FileManager.default.fileExists(atPath: second.path()))
        #expect(FileManager.default.fileExists(atPath: third.path()))
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

    @Test func 늦게_온_종료_요청은_새로_시작한_기록을_닫지_않고_같은_초에_시작해도_폴더가_겹치지_않는다() throws {
        let (recorder, root) = makeRecorder()
        defer { try? FileManager.default.removeItem(at: root) }
        let start = Date(timeIntervalSinceReferenceDate: 3_000)
        let first = try recorder.start(meta: meta(start))
        // 화면이 다시 나타나며 같은 초에 새 기록이 시작된 상황
        let second = try recorder.start(meta: meta(start.addingTimeInterval(0.07)))
        #expect(first.id != second.id)
        #expect(recorder.activeSessionID == second.id)

        // 첫 화면이 사라질 때 보낸 종료 요청이 늦게 도착해도 새 기록은 열려 있다.
        #expect(recorder.finish(sessionID: first.id) == nil)
        #expect(recorder.isRecording)
        #expect(recorder.finish(sessionID: second.id)?.id == second.id)
        #expect(!recorder.isRecording)
    }

    @Test func 자동으로_시작해_3초도_안_돼_끝난_기록은_남기지_않는다() throws {
        let (recorder, root) = makeRecorder()
        defer { try? FileManager.default.removeItem(at: root) }
        var automatic = meta(Date())
        automatic.isAutomatic = true
        let info = try recorder.start(meta: automatic)
        #expect(recorder.finish(sessionID: info.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: info.folderURL.path()))
        #expect(recorder.sessions().isEmpty)
    }
}
