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
        return true
    }
}

@main struct MyApp: App {
    @UIApplicationDelegateAdaptor(FirebaseAppDelegate.self) private var delegate
    @State private var store = Store(initialState: AppFeature.State()) { AppFeature() }

    var body: some Scene {
        WindowGroup {
            AppView(store: store)
        }
    }
}
