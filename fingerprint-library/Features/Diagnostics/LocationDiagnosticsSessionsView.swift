import ComposableArchitecture
import SwiftUI

/// 마이페이지에서 여는 위치 측정 기록 목록
/// - Note: 디자인 시안 없이 실험용으로 만든 화면이다(디자이너 미합의). 실험 브랜치 전용이며 출시 화면이 아니다.
struct LocationDiagnosticsSessionsView: View {
    let store: StoreOf<LocationDiagnosticsSessionsFeature>

    var body: some View {
        LocationDiagnosticsSessionListContent(
            sessions: store.sessions, recordingSessionID: nil, isBusy: store.isLoading,
            onDelete: { store.send(.deleteTapped($0)) })
        .navigationTitle("위치 측정 기록")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { store.send(.task) }
    }
}

/// 기록 목록 본문. 안내 화면의 진단 패널과 마이페이지가 함께 쓴다.
/// - Note: 디자인 시안 없이 실험용으로 만든 화면이다(디자이너 미합의).
struct LocationDiagnosticsSessionListContent: View {
    let sessions: [LocationDiagnosticsSessionInfo]
    /// 지금 기록 중인 세션은 내보내기·삭제를 막는다.
    let recordingSessionID: String?
    let isBusy: Bool
    var busyMessage = "기록을 불러오고 있어요"
    let onDelete: (String) -> Void

    var body: some View {
        List {
            if isBusy {
                HStack { ProgressView(); Text(busyMessage) }
            }
            ForEach(sessions) { session in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(session.id).font(.headline.monospacedDigit())
                        if session.meta?.isAutomatic == true { Text("자동").font(.caption).foregroundStyle(.secondary) }
                        if session.id == recordingSessionID { Text("기록 중").foregroundStyle(.red) }
                    }
                    Text(Self.detail(session)).font(.footnote).foregroundStyle(.secondary)
                    if let summary = session.summary { Text(summary.headline).font(.footnote) }
                    if session.id != recordingSessionID {
                        ShareLink(items: session.fileURLs) {
                            Label("내보내기 (\(session.fileURLs.count)개 파일)", systemImage: "square.and.arrow.up")
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.vertical, 4)
                .swipeActions {
                    if session.id != recordingSessionID {
                        Button("삭제", role: .destructive) { onDelete(session.id) }
                    }
                }
            }
            if sessions.isEmpty, !isBusy {
                ContentUnavailableView("기록이 없어요", systemImage: "waveform.path.ecg",
                                       description: Text("측정 모드에서 길안내를 하면 기록이 쌓여요."))
            }
        }
    }

    static func detail(_ session: LocationDiagnosticsSessionInfo) -> String {
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
