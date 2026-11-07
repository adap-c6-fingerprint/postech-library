import SwiftUI

struct AnalyticsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var choice = AnalyticsRuntime.shared.consent
    @State private var allowsSessionReplay = SessionReplayRuntime.shared.consent.enabled
    @State private var showsDiagnosticConfirmation = false
    let isFirstChoice: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("사용 분석 허용 (선택)", isOn: $choice.analytics)
                } footer: {
                    Text("Firebase / Google Analytics로 화면 이용 시간, 검색·도서 선택·길안내 행동과 임의의 설치 식별자, 학과 코드, 관심 분야 개수를 보내 서비스 개선에 사용합니다. 검색어 원문과 관심 분야 전체 목록은 보내지 않습니다.")
                }
                Section {
                    Toggle("오류 진단 허용 (선택)", isOn: $choice.diagnostics)
                } footer: {
                    Text("Firebase Crashlytics로 오류·크래시 기록과 기기·앱 정보, 오류 직전의 화면·행동 코드를 보냅니다. 처음 동의한 뒤 앱을 다시 실행하면 진단 대상 실행이 시작됩니다. 실행 내내 동의가 유지된 보고서만 다음 실행에서 전송합니다.")
                }
                Section {
                    Toggle("화면 이용 녹화 허용 (선택)", isOn: $allowsSessionReplay)
                } footer: {
                    Text("Microsoft Clarity로 화면의 텍스트·이미지와 탭·스크롤 등 이용 과정을 기록해 UX 개선에 사용합니다. API로 불러온 도서 정보·표지, 검색 화면, 소속·관심 분야 선택, 지도에 표시되는 위치·층·경로도 녹화에 포함될 수 있습니다. 데이터 수집 설정과 개발용 Mac 연결 설정에서는 녹화를 멈춥니다. GA 사용 분석과 별개로 선택할 수 있습니다.")
                }
                Section {
                    Text("좌표·층·서가 위치를 별도 분석 이벤트로 전송하지 않습니다. 다만 화면 이용 녹화를 허용하면 지도와 화면에 표시된 위치 정보가 Microsoft Clarity에 전송될 수 있습니다.")
                    Text("모두 거부해도 도서 검색과 길안내를 이용할 수 있습니다. 마이페이지에서 선택을 바꿀 수 있습니다. 철회하면 이후 분석 수집을 중단하며 이미 서버에 전송된 정보는 자동 삭제되지 않습니다.")
                }
                Section {
                    Button("선택 저장") { save(choice, sessionReplay: allowsSessionReplay) }
                    Button("모두 거부") { save(AnalyticsConsent(), sessionReplay: false) }
                }
                #if DEBUG
                Section("개발 검증") {
                    Button("비치명 오류 테스트 기록") { showsDiagnosticConfirmation = true }
                        .disabled(!AnalyticsRuntime.shared.canRecordDiagnosticTest)
                    Text("진단 동의를 저장하고 앱을 한 번 다시 실행한 뒤 테스트하세요. 앱을 종료하지 않으며 다음 실행에서 보고됩니다.")
                        .font(.footnote)
                }
                #endif
            }
            .navigationTitle("데이터 수집 설정")
            .toolbar {
                if !isFirstChoice {
                    ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                }
            }
            .confirmationDialog("테스트 오류를 기록할까요?", isPresented: $showsDiagnosticConfirmation) {
                #if DEBUG
                Button("기록") { AnalyticsRuntime.shared.recordDiagnosticTest() }
                #endif
            }
        }
        .interactiveDismissDisabled(isFirstChoice)
        .analyticsScreen(.analyticsSettings)
        // 동의 저장 시점부터 화면이 닫힐 때까지도 녹화를 중지한다.
        .sessionReplayProtected()
    }

    private func save(_ choice: AnalyticsConsent, sessionReplay: Bool) {
        SessionReplayRuntime.shared.saveConsent(enabled: sessionReplay)
        AnalyticsRuntime.shared.saveConsent(choice)
        dismiss()
    }
}
