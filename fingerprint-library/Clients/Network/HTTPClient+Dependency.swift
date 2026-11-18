import ComposableArchitecture
import Foundation

extension HTTPClient: DependencyKey {
    static let liveValue: Self = {
        #if DEMO
        // 오프라인 시연 빌드는 번들에 녹화한 응답만 사용한다.
        return .demoReplay()
        #elseif DEBUG
        if let path = ProcessInfo.processInfo.environment["POBOOK_DEMO_RECORD_DIR"], !path.isEmpty {
            return .demoRecording(into: URL(filePath: path, directoryHint: .isDirectory))
        }
        return .urlSession()
        #else
        return .urlSession()
        #endif
    }()
    static let testValue = Self(load: { _ in throw URLError(.unsupportedURL) })
}

nonisolated extension DependencyValues {
    nonisolated var httpClient: HTTPClient {
        get { self[HTTPClient.self] }
        set { self[HTTPClient.self] = newValue }
    }
}
