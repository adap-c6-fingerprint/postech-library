import Foundation

nonisolated enum AppConfiguration {
    static func relayConfiguration() throws -> APIRelayConfiguration {
        let channel = value(for: "POBOOK_BUILD_CHANNEL") ?? "automatic"
        guard ["automatic", "internal"].contains(channel) else { throw APIRelayError.invalidBuildChannel }
        let environment: APIRelayEnvironment
        #if DEBUG || targetEnvironment(simulator)
        environment = .development
        #else
        // TestFlight에서 검증한 바이너리를 App Store에 제출하므로 두 배포에서 운영 중계 서버를 사용한다.
        environment = channel == "internal" ? .development : .production
        #endif
        guard let token = value(for: "POBOOK_RELAY_TOKEN_\(environment.rawValue)") else {
            throw APIRelayError.missingAccessToken
        }
        return APIRelayConfiguration(environment: environment, token: token)
    }

    private static func value(for key: String) -> String? {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
            !value.isEmpty,
            !value.hasPrefix("$(")
        else {
            return nil
        }

        return value
    }
}
