import CoreLocation
import Foundation
import os

nonisolated struct LocationDiagnosticsSessionInfo: Equatable, Identifiable, Sendable {
    let id: String
    let folderURL: URL
    let meta: LocationDiagnosticsSessionMeta?
    let summary: LocationDiagnosticsSummary?
    let fileURLs: [URL]

    var isFinished: Bool { meta?.endedAt != nil }
    var totalBytes: Int64 {
        fileURLs.reduce(0) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}

/// 진단 세션 폴더(Documents/LocationDiagnostics/<id>)에 JSONL을 이어 쓴다.
/// 위치 Provider·모션·화면 녹화·안내 Feature가 여러 스레드에서 부르므로 내부 큐 하나로 직렬화한다.
nonisolated final class LocationDiagnosticsRecorder: @unchecked Sendable {
    static let shared = LocationDiagnosticsRecorder(rootURL: defaultRootURL)

    static let recordsFileName = "session.jsonl"
    static let metaFileName = "meta.json"
    static let summaryFileName = "summary.json"
    static let geoJSONFileName = "track.geojson"
    static let screenFileName = "screen.mp4"
    static let minimumAutomaticSessionSeconds = 3.0

    private struct ActiveSession {
        var meta: LocationDiagnosticsSessionMeta
        let folderURL: URL
        let handle: FileHandle
        var buffer = Data()
        var bufferedLines = 0
        var lastFlush = Date()
    }

    private let queue = DispatchQueue(label: "LocationDiagnosticsRecorder")
    private let activeFlag = OSAllocatedUnfairLock(initialState: false)
    private let encoder = LocationDiagnosticsCoding.encoder()
    private var active: ActiveSession?
    private let logger = Logger(subsystem: "fingerprint-library", category: "LocationDiagnostics")

    let rootURL: URL
    var isRecording: Bool { activeFlag.withLock { $0 } }

    static var defaultRootURL: URL {
        URL.documentsDirectory.appending(path: "LocationDiagnostics", directoryHint: .isDirectory)
    }

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    var activeFolderURL: URL? { queue.sync { active?.folderURL } }
    var activeSessionID: String? { queue.sync { active?.meta.sessionID } }

    // MARK: - 세션

    func start(meta: LocationDiagnosticsSessionMeta) throws -> LocationDiagnosticsSessionInfo {
        try queue.sync {
            if active != nil { _ = finishLocked() }
            // 같은 초에 두 번 시작해도 이전 기록을 덮어쓰지 않도록 이름이 겹치면 번호를 붙인다.
            var id = Self.sessionID(for: meta.startedAt)
            var suffix = 2
            while FileManager.default.fileExists(atPath: rootURL.appending(path: id, directoryHint: .isDirectory).path()) {
                id = Self.sessionID(for: meta.startedAt) + "-\(suffix)"
                suffix += 1
            }
            let folder = rootURL.appending(path: id, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let recordsURL = folder.appending(path: Self.recordsFileName)
            FileManager.default.createFile(atPath: recordsURL.path(), contents: nil)
            let handle = try FileHandle(forWritingTo: recordsURL)
            var meta = meta
            meta.sessionID = id
            try writeJSON(meta, to: folder.appending(path: Self.metaFileName))
            active = ActiveSession(meta: meta, folderURL: folder, handle: handle)
            activeFlag.withLock { $0 = true }
            appendLocked(.event(.init(at: meta.startedAt, name: "session_started",
                                      detail: ["posture": meta.posture.rawValue])))
            return Self.info(folder: folder)
        }
    }

    func updateMeta(_ change: @Sendable @escaping (inout LocationDiagnosticsSessionMeta) -> Void) {
        queue.async { [self] in
            guard var session = active else { return }
            change(&session.meta)
            active = session
            try? writeJSON(session.meta, to: session.folderURL.appending(path: Self.metaFileName))
        }
    }

    /// 기록을 닫고 요약·GeoJSON을 만든다.
    func finish() -> LocationDiagnosticsSessionInfo? {
        queue.sync { finishLocked() }
    }

    /// 지금 열린 기록이 `id`일 때만 닫는다. 늦게 도착한 종료 요청이 새 기록을 닫지 않게 한다.
    func finish(sessionID id: String) -> LocationDiagnosticsSessionInfo? {
        queue.sync { active?.meta.sessionID == id ? finishLocked() : nil }
    }

    private func finishLocked() -> LocationDiagnosticsSessionInfo? {
        guard active != nil else { return nil }
        // 마지막 줄을 버퍼에 넣은 뒤의 상태를 꺼내야 함께 저장된다.
        appendLocked(.event(.init(at: Date(), name: "session_finished")))
        guard var session = active else { return nil }
        flushLocked(&session)
        try? session.handle.close()
        active = nil
        activeFlag.withLock { $0 = false }
        let endedAt = Date()
        session.meta.endedAt = endedAt
        // 자동 측정은 안내 화면이 잠깐 사라졌다 다시 나타날 때도 시작·종료된다. 이런 순간 기록은 남기지 않는다.
        if session.meta.isAutomatic == true,
           endedAt.timeIntervalSince(session.meta.startedAt) < Self.minimumAutomaticSessionSeconds {
            try? FileManager.default.removeItem(at: session.folderURL)
            return nil
        }
        try? writeJSON(session.meta, to: session.folderURL.appending(path: Self.metaFileName))
        Self.writeDerivedFiles(in: session.folderURL)
        return Self.info(folder: session.folderURL)
    }

    /// 요약·GeoJSON을 기록 파일에서 다시 만든다. 앱이 중간에 종료된 세션도 목록에서 복구할 수 있다.
    static func writeDerivedFiles(in folder: URL) {
        let records = readRecords(in: folder)
        let encoder = LocationDiagnosticsCoding.encoder(pretty: true)
        if let data = try? encoder.encode(LocationDiagnosticsAnalyzer.summarize(records)) {
            try? data.write(to: folder.appending(path: summaryFileName), options: .atomic)
        }
        let geoJSON = LocationDiagnosticsGeoJSON.featureCollection(records)
        if let data = try? JSONSerialization.data(withJSONObject: geoJSON, options: [.prettyPrinted]) {
            try? data.write(to: folder.appending(path: geoJSONFileName), options: .atomic)
        }
    }

    static func readRecords(in folder: URL) -> [LocationDiagnosticsRecord] {
        guard let text = try? String(contentsOf: folder.appending(path: recordsFileName), encoding: .utf8) else { return [] }
        let decoder = LocationDiagnosticsCoding.decoder()
        return text.split(separator: "\n").compactMap {
            try? decoder.decode(LocationDiagnosticsRecord.self, from: Data($0.utf8))
        }
    }

    func sessions() -> [LocationDiagnosticsSessionInfo] {
        let activeID = queue.sync { active?.meta.sessionID }
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return folders
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { folder in
                // 비정상 종료로 요약이 없는 세션은 지금 만든다.
                if folder.lastPathComponent != activeID,
                   !FileManager.default.fileExists(atPath: folder.appending(path: Self.summaryFileName).path()) {
                    Self.writeDerivedFiles(in: folder)
                }
                return Self.info(folder: folder)
            }
            .sorted { $0.id > $1.id }
    }

    func delete(id: String) {
        guard queue.sync(execute: { active?.meta.sessionID != id }) else { return }
        try? FileManager.default.removeItem(at: rootURL.appending(path: id, directoryHint: .isDirectory))
    }

    // MARK: - 기록

    func append(_ record: LocationDiagnosticsRecord) {
        guard isRecording else { return }
        queue.async { [self] in appendLocked(record) }
    }

    func recordLocation(_ location: CLLocation, receivedAt: Date) {
        guard isRecording else { return }
        let finite: (Double) -> Double? = { $0.isFinite && $0 >= 0 ? $0 : nil }
        append(.location(.init(
            receivedAt: receivedAt, timestamp: location.timestamp,
            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: finite(location.verticalAccuracy),
            altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
            floorLevel: location.floor?.level,
            speed: finite(location.speed), speedAccuracy: finite(location.speedAccuracy),
            course: finite(location.course), courseAccuracy: finite(location.courseAccuracy),
            isSimulatedBySoftware: location.sourceInformation?.isSimulatedBySoftware,
            isProducedByAccessory: location.sourceInformation?.isProducedByAccessory
        )))
    }

    func recordHeading(_ heading: CLHeading, receivedAt: Date) {
        guard isRecording else { return }
        append(.heading(.init(receivedAt: receivedAt, timestamp: heading.timestamp,
                              trueHeading: heading.trueHeading, magneticHeading: heading.magneticHeading,
                              headingAccuracy: heading.headingAccuracy)))
    }

    func flush() {
        queue.async { [self] in
            guard var session = active else { return }
            flushLocked(&session)
            active = session
        }
    }

    private func appendLocked(_ record: LocationDiagnosticsRecord) {
        guard var session = active, let line = try? encoder.encode(record) else { return }
        session.buffer.append(line)
        session.buffer.append(0x0A)
        session.bufferedLines += 1
        if session.bufferedLines >= 32 || Date().timeIntervalSince(session.lastFlush) >= 2 {
            flushLocked(&session)
        }
        active = session
    }

    private func flushLocked(_ session: inout ActiveSession) {
        guard !session.buffer.isEmpty else { return }
        do {
            try session.handle.seekToEnd()
            try session.handle.write(contentsOf: session.buffer)
        } catch {
            logger.error("진단 기록 쓰기 실패: \(error.localizedDescription, privacy: .public)")
        }
        session.buffer.removeAll(keepingCapacity: true)
        session.bufferedLines = 0
        session.lastFlush = Date()
    }

    private func writeJSON(_ value: some Encodable, to url: URL) throws {
        try LocationDiagnosticsCoding.encoder(pretty: true).encode(value).write(to: url, options: .atomic)
    }

    // MARK: - 목록 정보

    private static func sessionID(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static func info(folder: URL) -> LocationDiagnosticsSessionInfo {
        let decoder = LocationDiagnosticsCoding.decoder()
        let meta = (try? Data(contentsOf: folder.appending(path: metaFileName)))
            .flatMap { try? decoder.decode(LocationDiagnosticsSessionMeta.self, from: $0) }
        let summary = (try? Data(contentsOf: folder.appending(path: summaryFileName)))
            .flatMap { try? decoder.decode(LocationDiagnosticsSummary.self, from: $0) }
        let order = [recordsFileName, summaryFileName, metaFileName, geoJSONFileName, screenFileName]
        let files = order.map { folder.appending(path: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path()) }
        return .init(id: folder.lastPathComponent, folderURL: folder, meta: meta, summary: summary, fileURLs: files)
    }
}
