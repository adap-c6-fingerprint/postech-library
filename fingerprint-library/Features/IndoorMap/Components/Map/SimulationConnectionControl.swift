#if DEBUG
import SwiftUI

/// Debug 지도에서 앱 재실행 없이 위치 공급자와 Mac 연결을 전환한다.
struct SimulationConnectionControl: View {
    let position: IndoorPosition?
    let floorName: String?
    let message: String?
    let onReconnect: () -> Void
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label("시뮬레이터", systemImage: "link")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("simulation-connection-button")
        .sheet(isPresented: $isPresented) {
            SimulationConnectionSheet(position: position, floorName: floorName,
                                      message: message, onReconnect: onReconnect)
        }
    }
}

private struct SimulationConnectionSheet: View {
    let position: IndoorPosition?
    let floorName: String?
    let message: String?
    let onReconnect: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var usesSimulation = true
    @State private var host = ""
    @State private var port = "57575"
    @State private var validationMessage: String?

    private var isReceiving: Bool {
        position?.source == .simulation && position?.isRecent(at: Date()) == true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("연결 상태") {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let receiving = position?.source == .simulation
                            && position?.isRecent(at: context.date) == true
                        Label(receiving ? "Mac 위치 수신 중" : status,
                              systemImage: receiving ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                            .foregroundStyle(receiving ? Color.green : Color.secondary)
                            .accessibilityIdentifier("simulation-connection-status")
                    }
                    if isReceiving, let floorName {
                        LabeledContent("현재 위치", value: floorName)
                    }
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                }

                Section {
                    Toggle("Mac 시뮬레이터 사용", isOn: $usesSimulation)
                        .accessibilityIdentifier("simulation-enabled")
                    if usesSimulation {
                        TextField("Mac 주소", text: $host, prompt: Text("비워 두면 자동 연결"))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("simulation-host")
                        TextField("포트", text: $port)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("simulation-port")
                    }
                } header: {
                    Text("연결 설정")
                } footer: {
                    Text("iOS Simulator는 현재 Mac에 자동 연결합니다. 실제 iPhone은 같은 Wi-Fi의 Mac을 검색합니다. Mac의 ‘블루닷 연결 준비’를 먼저 눌러주세요.")
                }

                Section {
                    Button(usesSimulation ? "연결 / 다시 연결" : "실제 위치로 전환") { apply() }
                        .accessibilityIdentifier("simulation-reconnect")
                    Button("실행 설정으로 되돌리기") {
                        IndoorSimulationSettings.reset()
                        reload()
                        onReconnect()
                    }
                    if let validationMessage {
                        Text(validationMessage).font(.caption).foregroundStyle(.red)
                    }
                } footer: {
                    Text("선택한 설정은 Debug 앱에 저장됩니다. 앱을 다시 켜도 유지되며 이 화면에서 실제 위치로 전환할 수 있습니다.")
                }
            }
            .navigationTitle("위치 시뮬레이터")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .onAppear { reload() }
        }
        .presentationDetents([.large])
    }

    private var status: String {
        IndoorLocationClient.usesSimulation ? "Mac 연결 대기 중" : "실제 위치 사용 중"
    }

    private func reload() {
        let settings = IndoorSimulationSettings.load()
        usesSimulation = settings.usesSimulation(environment: ProcessInfo.processInfo.environment,
                                                isSimulator: IndoorSimulationConfiguration.isSimulator)
        // 저장한 값이 없을 때만 실행 환경의 직접 주소를 표시한다.
        host = settings.host ?? ProcessInfo.processInfo.environment["INDOOR_SIMULATOR_HOST"] ?? ""
        port = settings.port.map(String.init)
            ?? ProcessInfo.processInfo.environment["INDOOR_SIMULATOR_PORT"] ?? "57575"
        validationMessage = nil
    }

    private func apply() {
        let settings: IndoorSimulationSettings
        if usesSimulation {
            guard let number = UInt16(port.trimmingCharacters(in: .whitespacesAndNewlines)), number > 0 else {
                validationMessage = "포트는 1부터 65535 사이의 숫자로 입력해주세요."
                return
            }
            settings = IndoorSimulationSettings(source: .simulation,
                host: host.trimmingCharacters(in: .whitespacesAndNewlines), port: number)
        } else {
            settings = IndoorSimulationSettings(source: .live)
        }
        do {
            if usesSimulation {
                _ = try settings.connection(environment: ProcessInfo.processInfo.environment,
                                            isSimulator: IndoorSimulationConfiguration.isSimulator)
            }
            try settings.save()
            validationMessage = nil
            onReconnect()
        } catch {
            validationMessage = "Mac 주소를 확인해주세요. 호스트 이름이나 IP 주소만 입력합니다."
        }
    }
}
#endif
