import ComposableArchitecture
import SwiftUI

/// 기록 중 안내 화면 위에 띄우는 실시간 수치. 영상과 시점을 맞추도록 밀리초 시계를 함께 보여 준다.
/// - Note: 디자인 시안 없이 실험용으로 만든 화면이다(디자이너 미합의). 실험 브랜치 전용이며 출시 화면이 아니다.
struct BookNavigationDiagnosticsHUD: View {
    let store: StoreOf<BookNavigationFeature>
    @State private var isFlashing = false

    private var diagnostics: BookNavigationFeature.Diagnostics { store.diagnostics }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 8, height: 8).accessibilityHidden(true)
                    Text("\(diagnostics.isAutoMode ? "AUTO REC" : "REC") \(elapsed(at: context.date))")
                    Text(context.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second()
                        .secondFraction(.fractional(3))))
                    if let screen = screenLabel { Text(screen) }
                }
            }
            Text(positionLine)
            Text(guidanceLine)
            if let tracking = trackingLine { Text(tracking) }
            HStack(spacing: 8) {
                Button { store.send(.diagnostics(.jumpMarkerTapped)) } label: {
                    Label("튐! \(diagnostics.jumpMarkerCount)", systemImage: "bolt.fill")
                        .frame(minHeight: 44).padding(.horizontal, 12)
                        .background(.orange.opacity(0.85), in: Capsule())
                }
                .accessibilityHint("지금 위치가 튀었다고 기록해요")
                .accessibilityIdentifier("diagnostics-jump-marker")
                Button { store.send(.diagnostics(.checkpointModeTapped)) } label: {
                    Label("기준점 \(diagnostics.checkpointCount)", systemImage: "scope")
                        .frame(minHeight: 44).padding(.horizontal, 12)
                        .background(.blue.opacity(0.85), in: Capsule())
                }
                .accessibilityHint("지도에서 실제 내 위치를 지정해요")
                .accessibilityIdentifier("diagnostics-checkpoint")
            }
            .buttonStyle(.plain)
            .font(.footnote.weight(.semibold))
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.white)
        .padding(10)
        .background(.black.opacity(isFlashing ? 0.2 : 0.72), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(.white, lineWidth: isFlashing ? 4 : 0)
        }
        .onChange(of: diagnostics.markerFlashID) { _, _ in
            isFlashing = true
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                isFlashing = false
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(diagnostics.isAutoMode ? "위치 자동 측정 중" : "위치 진단 기록 중")
        .accessibilityIdentifier("diagnostics-hud")
    }

    private func elapsed(at date: Date) -> String {
        guard let startedAt = diagnostics.startedAt else { return "--:--" }
        let seconds = max(0, Int(date.timeIntervalSince(startedAt)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var screenLabel: String? {
        switch diagnostics.screenStatus {
        case .idle: nil
        case .requesting: "화면 승인 대기"
        case .recording: "화면 녹화 중"
        case .finished: "화면 저장됨"
        case .cancelled: "화면 녹화 취소"
        case .failed: "화면 녹화 실패"
        case .unavailable: "화면 녹화 불가"
        }
    }

    private var positionLine: String {
        var parts: [String] = []
        if let position = store.rawPosition {
            parts.append(position.horizontalAccuracy.map { "±\(Self.format($0))m" } ?? "±?m")
            parts.append(position.floorOrdinal.map { "층 \($0)" } ?? "층 ?")
        } else {
            parts.append("위치 없음")
        }
        if let jump = diagnostics.lastJump {
            let speed = jump.metersPerSecond.map { " \(Self.format($0))m/s" } ?? ""
            parts.append("이동 \(Self.format(jump.meters))m\(speed)\(jump.isJump ? " 튐" : "")")
        }
        return parts.joined(separator: " · ")
    }

    private var guidanceLine: String {
        var parts = [diagnostics.lastQuality ?? "판정 대기"]
        if let distance = diagnostics.lastDistanceToRoute { parts.append("경로까지 \(Self.format(distance))m") }
        if let remaining = store.displayedProgress?.remainingMeters { parts.append("남은 \(Self.format(remaining))m") }
        return parts.joined(separator: " · ")
    }

    /// 위치 추정기 상태: 측정 오차가 커서 추정에 기대는 중인지, 위치를 잃었는지
    private var trackingLine: String? {
        guard let status = store.trackingStatus else { return nil }
        let label = switch status {
        case .tracking: "추적 중"
        case .degraded: "불안정(추정 유지)"
        case .lost: "위치 잃음"
        }
        let uncertainty = store.tracker?.uncertaintyMeters.map { " · 추정 ±\(Self.format($0))m" } ?? ""
        return label + uncertainty
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

/// 기준점 지정 중 지도 중앙에 겹쳐 보이는 십자선
struct BookNavigationDiagnosticsCrosshair: View {
    var body: some View {
        ZStack {
            Circle().strokeBorder(.yellow, lineWidth: 2).frame(width: 36, height: 36)
            Rectangle().fill(.yellow).frame(width: 2, height: 56)
            Rectangle().fill(.yellow).frame(width: 56, height: 2)
        }
        .shadow(color: .black.opacity(0.6), radius: 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 기준점 지정 안내와 확인 버튼
struct BookNavigationCheckpointBar: View {
    let store: StoreOf<BookNavigationFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("지도를 움직여 노란 십자선을 지금 서 있는 실제 위치에 맞춘 뒤 ‘여기예요’를 눌러 주세요.")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("취소") { store.send(.diagnostics(.checkpointCancelled)) }
                    .buttonStyle(.bordered)
                Spacer()
                Button("여기예요") { store.send(.diagnostics(.checkpointConfirmed)) }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.diagnostics.checkpointCenter == nil)
                    .accessibilityIdentifier("diagnostics-checkpoint-confirm")
            }
            .controlSize(.large)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
    }
}
