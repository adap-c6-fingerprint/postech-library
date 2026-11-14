import Foundation
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

nonisolated enum ScreenRecordingStatus: Equatable, Sendable {
    case idle
    case requesting
    case recording(startedAt: Date)
    case finished(URL)
    case cancelled
    case failed(String)
    case unavailable

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }
}

#if canImport(ScreenCaptureKit)
/// iOS 27 ScreenCaptureKit으로 이 앱 화면만 녹화한다.
/// 시스템 선택 화면에서 사용자가 허용해야 시작되며, 녹화 시작 시각을 진단 기록에 남겨 위치 기록과 시점을 맞춘다.
@available(iOS 27.0, *)
final class ScreenRecordingProvider: NSObject {
    static let shared = ScreenRecordingProvider()

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var outputURL: URL?
    private var recorder: LocationDiagnosticsRecorder?
    private var isObserving = false
    private var continuations: [UUID: AsyncStream<ScreenRecordingStatus>.Continuation] = [:]
    private(set) var status: ScreenRecordingStatus = .idle {
        didSet { for continuation in continuations.values { continuation.yield(status) } }
    }

    var isAvailable: Bool { SCContentSharingPicker.shared.isAvailable }

    func statusUpdates() -> AsyncStream<ScreenRecordingStatus> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: ScreenRecordingStatus.self,
                                                            bufferingPolicy: .bufferingNewest(4))
        continuations[id] = continuation
        continuation.yield(status)
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations.removeValue(forKey: id) }
        }
        return stream
    }

    func start(outputURL: URL, includesMicrophone: Bool, recorder: LocationDiagnosticsRecorder) {
        let picker = SCContentSharingPicker.shared
        guard picker.isAvailable else {
            status = .unavailable
            return
        }
        self.outputURL = outputURL
        self.recorder = recorder
        if !isObserving {
            picker.add(self)
            isObserving = true
        }
        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = includesMicrophone
        picker.defaultConfiguration = configuration
        picker.isActive = true
        status = .requesting
        picker.presentForCurrentApplication()
    }

    func stop() async {
        guard let stream else {
            deactivatePicker()
            if status == .requesting { status = .cancelled }
            return
        }
        do {
            try await stream.stopCapture()
        } catch {
            status = .failed(error.localizedDescription)
        }
        self.stream = nil
        // 파일 마무리는 recordingOutputDidFinishRecording에서 알린다. 콜백이 늦어도 기록 종료는 막지 않는다.
        for _ in 0..<20 where status.isRecording {
            try? await Task.sleep(for: .milliseconds(100))
        }
        deactivatePicker()
    }

    private func deactivatePicker() {
        let picker = SCContentSharingPicker.shared
        picker.isActive = false
        if isObserving {
            picker.remove(self)
            isObserving = false
        }
    }

    private func begin(filter: SCContentFilter) async {
        guard let outputURL else { return }
        let configuration = SCStreamConfiguration()
        let scale = Double(filter.pointPixelScale)
        if filter.contentRect.width > 0, filter.contentRect.height > 0 {
            configuration.width = Int(filter.contentRect.width * scale)
            configuration.height = Int(filter.contentRect.height * scale)
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        let outputConfiguration = SCRecordingOutputConfiguration()
        outputConfiguration.outputURL = outputURL
        outputConfiguration.outputFileType = .mp4
        let output = SCRecordingOutput(configuration: outputConfiguration, delegate: self)
        do {
            try? FileManager.default.removeItem(at: outputURL)
            try stream.addRecordingOutput(output)
            self.stream = stream
            recordingOutput = output
            try await stream.startCapture()
        } catch {
            self.stream = nil
            recordingOutput = nil
            fail(error.localizedDescription)
        }
    }

    private func fail(_ message: String) {
        status = .failed(message)
        recorder?.append(.event(.init(at: Date(), name: "screen_recording_failed", detail: ["message": message])))
    }
}

@available(iOS 27.0, *)
extension ScreenRecordingProvider: SCContentSharingPickerObserver {
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in
            self.status = .cancelled
            self.recorder?.append(.event(.init(at: Date(), name: "screen_recording_cancelled")))
            self.deactivatePicker()
        }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter,
                                          for stream: SCStream?) {
        Task { @MainActor in await self.begin(filter: filter) }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.fail(message)
            self.deactivatePicker()
        }
    }
}

@available(iOS 27.0, *)
extension ScreenRecordingProvider: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.stream = nil
            self.fail(message)
        }
    }
}

@available(iOS 27.0, *)
extension ScreenRecordingProvider: SCRecordingOutputDelegate {
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        let startedAt = Date()
        Task { @MainActor in
            self.status = .recording(startedAt: startedAt)
            self.recorder?.append(.event(.init(at: startedAt, name: "screen_recording_started")))
            self.recorder?.updateMeta { $0.screenRecordingStartedAt = startedAt }
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.fail(message) }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        let finishedAt = Date()
        Task { @MainActor in
            self.recordingOutput = nil
            self.recorder?.append(.event(.init(at: finishedAt, name: "screen_recording_finished")))
            if let url = self.outputURL { self.status = .finished(url) }
        }
    }
}
#endif
