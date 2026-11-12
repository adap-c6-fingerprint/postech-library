import SwiftUI
import ComposableArchitecture
import FirebaseCore
import OSLog

final class FirebaseAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        guard FirebaseApp.app() == nil else { return true }
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path),
              options.bundleID == Bundle.main.bundleIdentifier else {
            // Firebase 설정 누락이 기존 도서·길안내 기능을 막지 않게 한다.
            Logger(subsystem: "com.youngmin.fingerprint-library", category: "Firebase")
                .error("Firebase configuration is missing or does not match this app; initialization skipped.")
            return true
        }
        FirebaseApp.configure(options: options)
        AnalyticsRuntime.shared.start()
        return true
    }
}

@main struct MyApp: App {
    @UIApplicationDelegateAdaptor(FirebaseAppDelegate.self) private var delegate
    /// 앱 루트 Store. 테스트 호스트로 실행될 때는 만들지 않는다.
    @MainActor static let store = Store(initialState: AppFeature.State()) { AppFeature() }

    var body: some Scene {
        WindowGroup {
            // 테스트가 앱을 호스트로 실행하면 앱 화면과 그 효과가 테스트 의존성을 건드리지 않게 비워 둔다.
            if isTesting {
                EmptyView()
            } else {
                AppView(store: Self.store)
            }
        }
    }
}
