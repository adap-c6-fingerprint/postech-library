import ComposableArchitecture
import SwiftUI

/// 진단 기록 시작·종료, 현장 마커, 기록 목록·내보내기를 모은 시트
/// - Note: 디자인 시안 없이 실험용으로 만든 화면이다(디자이너 미합의). 실험 브랜치 전용이며 출시 화면이 아니다.
struct BookNavigationDiagnosticsPanel: View {
    @Bindable var store: StoreOf<BookNavigationFeature>
    @Environment(\.dismiss) private var dismiss

    private var diagnostics: BookNavigationFeature.Diagnostics { store.diagnostics }

    var body: some View {
        NavigationStack {
            Form {
                if diagnostics.isAutoMode {
                    autoModeSection
                    if diagnostics.isRecording { markerSection }
                } else if diagnostics.isRecording {
                    recordingSection
                } else {
                    setupSection
                }
                Section {
                    NavigationLink("기록 목록·내보내기") {
                        BookNavigationDiagnosticsSessionList(store: store)
                    }
                    .accessibilityIdentifier("diagnostics-session-list")
                } footer: {
                    Text("기록은 이 기기에만 저장돼요. 파일 앱 › 나의 iPhone › Po:book › LocationDiagnostics에서도 볼 수 있어요.")
                }
            }
            .navigationTitle("위치 진단")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private var setupSection: some View {
        Section {
            Picker("기기 자세", selection: Binding(get: { diagnostics.posture },
                                              set: { store.send(.diagnostics(.postureChanged($0))) })) {
                ForEach(LocationDiagnosticsPosture.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Toggle("화면 녹화", isOn: Binding(get: { diagnostics.includesScreenRecording },
                                          set: { store.send(.diagnostics(.screenRecordingToggled($0))) }))
                .disabled(!diagnostics.isScreenRecordingAvailable)
            if diagnostics.includesScreenRecording {
                Toggle("음성 메모(마이크)", isOn: Binding(get: { diagnostics.includesMicrophone },
                                                     set: { store.send(.diagnostics(.microphoneToggled($0))) }))
            }
            Button {
                store.send(.diagnostics(.startTapped))
            } label: {
                if diagnostics.isStarting { ProgressView() } else { Text("기록 시작") }
            }
            .disabled(diagnostics.isStarting || diagnostics.isFinishing)
            .accessibilityIdentifier("diagnostics-start")
            if let message = diagnostics.errorMessage {
                Text(message).foregroundStyle(.red)
            }
            if let session = diagnostics.lastFinishedSession {
                VStack(alignment: .leading, spacing: 4) {
                    Text("방금 기록: \(session.id)").font(.subheadline.weight(.semibold))
                    if let summary = session.summary { Text(summary.headline).font(.footnote) }
                    ShareLink(items: session.fileURLs) { Label("내보내기", systemImage: "square.and.arrow.up") }
                }
            }
        } header: {
            Text("새 기록")
        } footer: {
            Text(diagnostics.isScreenRecordingAvailable
                 ? "화면 녹화를 켜면 시작할 때 시스템 화면에서 앱 화면 녹화를 허용해 주세요. 음성 메모는 주변 사람 목소리가 함께 녹음될 수 있어요."
                 : "이 기기에서는 앱 화면 녹화를 쓸 수 없어요(iOS 27 실제 기기 필요). 제어 센터의 화면 기록을 대신 쓸 수 있어요.")
        }
    }

    /// 검색창 `/test` 측정 모드: 시작·종료 조작 없이 안내마다 자동으로 기록한다.
    private var autoModeSection: some View {
        Section {
            LabeledContent("상태", value: diagnostics.isRecording ? "자동 기록 중" : (diagnostics.isStarting ? "시작하는 중" : "대기"))
            if let startedAt = diagnostics.startedAt {
                LabeledContent("시작", value: startedAt.formatted(date: .omitted, time: .standard))
            }
            if let message = diagnostics.errorMessage {
                Text(message).foregroundStyle(.red)
            }
            Button("측정 모드 끄기", role: .destructive) { store.send(.diagnostics(.autoModeTurnedOff)) }
                .accessibilityIdentifier("diagnostics-auto-off")
        } header: {
            Text("자동 측정 모드")
        } footer: {
            Text("길안내를 시작하면 위치·안내 판정·걸음 기록이 자동으로 시작되고, 안내를 끝내면 저장돼요. 화면 녹화는 하지 않아요. 검색창에 /test를 다시 입력해도 꺼져요. 지금 기록은 측정 모드를 끄면 바로 저장돼요.")
        }
    }

    /// 자동 측정 중에도 실제 위치와 체감 튐은 사람이 남겨야 하므로 마커만 따로 둔다.
    private var markerSection: some View {
        Section {
            LabeledContent("기준점·튐 표시", value: "\(diagnostics.checkpointCount) · \(diagnostics.jumpMarkerCount)")
            Button("기준점 찍기 (지도 십자선)") { store.send(.diagnostics(.checkpointModeTapped)) }
            Button("목적지 서가 앞에 서 있어요") { store.send(.diagnostics(.destinationCheckpointTapped)) }
                .disabled(store.currentPlan == nil)
            Button("튐 표시") { store.send(.diagnostics(.jumpMarkerTapped)) }
        } header: {
            Text("현장 표시 (선택)")
        }
    }

    private var recordingSection: some View {
        Section {
            if let startedAt = diagnostics.startedAt {
                LabeledContent("시작", value: startedAt.formatted(date: .omitted, time: .standard))
            }
            LabeledContent("기준점·튐 표시", value: "\(diagnostics.checkpointCount) · \(diagnostics.jumpMarkerCount)")
            Button("기준점 찍기 (지도 십자선)") { store.send(.diagnostics(.checkpointModeTapped)) }
            Button("목적지 서가 앞에 서 있어요") { store.send(.diagnostics(.destinationCheckpointTapped)) }
                .disabled(store.currentPlan == nil)
            Button("튐 표시") { store.send(.diagnostics(.jumpMarkerTapped)) }
            Button(role: .destructive) {
                store.send(.diagnostics(.finishTapped))
            } label: {
                Text("기록 종료")
            }
            .accessibilityIdentifier("diagnostics-finish")
        } header: {
            Text("기록 중")
        } footer: {
            Text("안내를 종료하거나 화면을 닫아도 기록이 저장되고 끝나요.")
        }
    }
}

struct BookNavigationDiagnosticsSessionList: View {
    let store: StoreOf<BookNavigationFeature>

    var body: some View {
        List {
            if store.diagnostics.isFinishing {
                HStack { ProgressView(); Text("기록을 정리하고 있어요") }
            }
            ForEach(store.diagnostics.sessions) { session in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(session.id).font(.headline.monospacedDigit())
                        if session.id == store.diagnostics.session?.id { Text("기록 중").foregroundStyle(.red) }
                    }
                    Text(detail(session)).font(.footnote).foregroundStyle(.secondary)
                    if let summary = session.summary { Text(summary.headline).font(.footnote) }
                    if session.id != store.diagnostics.session?.id {
                        ShareLink(items: session.fileURLs) {
                            Label("내보내기 (\(session.fileURLs.count)개 파일)", systemImage: "square.and.arrow.up")
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.vertical, 4)
                .swipeActions {
                    if session.id != store.diagnostics.session?.id {
                        Button("삭제", role: .destructive) { store.send(.diagnostics(.deleteSessionTapped(session.id))) }
                    }
                }
            }
            if store.diagnostics.sessions.isEmpty, !store.diagnostics.isFinishing {
                ContentUnavailableView("기록이 없어요", systemImage: "waveform.path.ecg")
            }
        }
        .navigationTitle("기록 목록")
        .onAppear { store.send(.diagnostics(.sessionListAppeared)) }
    }

    private func detail(_ session: LocationDiagnosticsSessionInfo) -> String {
        var parts: [String] = []
        if let summary = session.summary {
            let seconds = Int(summary.durationSeconds)
            parts.append(String(format: "%d분 %02d초", seconds / 60, seconds % 60))
            parts.append("위치 \(summary.locationCount)건")
        }
        if let posture = session.meta?.posture { parts.append(posture.title) }
        parts.append(ByteCountFormatter.string(fromByteCount: session.totalBytes, countStyle: .file))
        if session.fileURLs.contains(where: { $0.lastPathComponent == LocationDiagnosticsRecorder.screenFileName }) {
            parts.append("화면 녹화 포함")
        }
        return parts.joined(separator: " · ")
    }
}
