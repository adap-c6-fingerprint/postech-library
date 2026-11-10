import Foundation
import StoreKit

nonisolated enum AppConfiguration {
    static func relayConfiguration() async throws -> APIRelayConfiguration {
        let channel = value(for: "POBOOK_BUILD_CHANNEL") ?? "automatic"
        guard ["automatic", "internal"].contains(channel) else { throw APIRelayError.invalidBuildChannel }
        let environment: APIRelayEnvironment
        #if DEBUG || targetEnvironment(simulator)
        environment = .development
        #else
        if channel == "internal" {
            environment = .development
        } else {
            // 같은 Release 바이너리를 구분한다. 검증 실패를 운영 환경으로 추측하지 않는다.
            guard case let .verified(transaction) = try await AppTransaction.shared else {
                throw APIRelayError.unknownDistribution
            }
            let distribution: APIRelayEnvironment.Distribution
            switch transaction.environment {
            case .xcode: distribution = .xcode
            case .sandbox: distribution = .sandbox
            case .production: distribution = .production
            default: throw APIRelayError.unknownDistribution
            }
            environment = try .select(internalBuild: false, distribution: distribution)
        }
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
