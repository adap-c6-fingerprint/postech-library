import ComposableArchitecture
import Foundation
import UIKit

/// 실시간 안내 위치 품질 진단 기록(실험 브랜치 전용). 기록은 기기 Documents에만 남고 밖으로 보내지 않는다.
nonisolated struct LocationDiagnosticsClient: Sendable {
    var isScreenRecordingAvailable: @Sendable () async -> Bool
    /// 기록 파일을 바로 열고 세션 정보를 돌려준다. 화면 작업이 취소돼도 결과를 잃지 않도록 동기로 처리한다.
    var startSession: @Sendable (LocationDiagnosticsSessionMeta) throws -> LocationDiagnosticsSessionInfo
    var startScreenRecording: @Sendable (_ includesMicrophone: Bool) async -> Void
    var finishSession: @Sendable () async -> LocationDiagnosticsSessionInfo?
    /// 안내 화면이 닫히며 Feature 작업이 취소돼도 기록을 끝까지 정리한다.
    /// 해당 세션이 아직 열려 있을 때만 닫는다.
    var finishSessionInBackground: @Sendable (_ sessionID: String) -> Void
    var record: @Sendable (LocationDiagnosticsRecord) -> Void
    var flush: @Sendable () -> Void
    var sessions: @Sendable () async -> [LocationDiagnosticsSessionInfo]
    var deleteSession: @Sendable (String) async -> Void
    var screenRecordingStatus: @Sendable () async -> AsyncStream<ScreenRecordingStatus>
}

extension LocationDiagnosticsClient: DependencyKey {
    static let liveValue = Self(
        isScreenRecordingAvailable: {
            #if canImport(ScreenCaptureKit)
            guard #available(iOS 27.0, *) else { return false }
            return await ScreenRecordingProvider.shared.isAvailable
            #else
            return false
            #endif
        },
        startSession: { meta in
            var meta = meta
            meta.deviceModel = Self.hardwareModel()
            meta.systemVersion = ProcessInfo.processInfo.operatingSystemVersionString
            let bundle = Bundle.main.infoDictionary
            meta.appVersion = bundle?["CFBundleShortVersionString"] as? String
            meta.appBuild = bundle?["CFBundleVersion"] as? String
            meta.isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            meta.thermalState = Self.thermalStateName(ProcessInfo.processInfo.thermalState)
            meta.locationSettings = ["desiredAccuracy": "best", "distanceFilter": "none", "activityType": "otherNavigation"]
            let recorder = LocationDiagnosticsRecorder.shared
            let info = try recorder.start(meta: meta)
            MotionDiagnosticsProvider.shared.start(recorder: recorder, from: meta.startedAt)
            return info
        },
        startScreenRecording: { includesMicrophone in
            let recorder = LocationDiagnosticsRecorder.shared
            guard let folder = recorder.activeFolderURL else { return }
            #if canImport(ScreenCaptureKit)
            guard #available(iOS 27.0, *) else {
                recorder.append(.event(.init(at: Date(), name: "screen_recording_unsupported_os")))
                return
            }
            await ScreenRecordingProvider.shared.start(
                outputURL: folder.appending(path: LocationDiagnosticsRecorder.screenFileName),
                includesMicrophone: includesMicrophone, recorder: recorder)
            #else
            recorder.append(.event(.init(at: Date(), name: "screen_recording_unsupported_platform")))
            #endif
        },
        finishSession: { await finishLive() },
        finishSessionInBackground: { sessionID in
            guard LocationDiagnosticsRecorder.shared.activeSessionID == sessionID else { return }
            Task.detached { _ = await finishLive(sessionID: sessionID) }
        },
        record: { LocationDiagnosticsRecorder.shared.append($0) },
        flush: { LocationDiagnosticsRecorder.shared.flush() },
        sessions: { LocationDiagnosticsRecorder.shared.sessions() },
        deleteSession: { LocationDiagnosticsRecorder.shared.delete(id: $0) },
        screenRecordingStatus: {
            #if canImport(ScreenCaptureKit)
            if #available(iOS 27.0, *) { return await ScreenRecordingProvider.shared.statusUpdates() }
            #endif
            return AsyncStream { $0.yield(.unavailable); $0.finish() }
        }
    )

    static let testValue = Self(
        isScreenRecordingAvailable: { false },
        startSession: { meta in
            .init(id: "test", folderURL: URL(filePath: "/dev/null"), meta: meta, summary: nil, fileURLs: [])
        },
        startScreenRecording: { _ in },
        finishSession: { nil },
        finishSessionInBackground: { _ in },
        record: { _ in },
        flush: {},
        sessions: { [] },
        deleteSession: { _ in },
        screenRecordingStatus: { AsyncStream { $0.finish() } }
    )

    private static func finishLive(sessionID: String? = nil) async -> LocationDiagnosticsSessionInfo? {
        let recorder = LocationDiagnosticsRecorder.shared
        if let sessionID, recorder.activeSessionID != sessionID { return nil }
        #if canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *) { await ScreenRecordingProvider.shared.stop() }
        #endif
        MotionDiagnosticsProvider.shared.stop()
        return sessionID.map { recorder.finish(sessionID: $0) } ?? recorder.finish()
    }

    private static func hardwareModel() -> String {
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private static func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}

nonisolated extension DependencyValues {
    var locationDiagnosticsClient: LocationDiagnosticsClient {
        get { self[LocationDiagnosticsClient.self] }
        set { self[LocationDiagnosticsClient.self] = newValue }
    }
}
