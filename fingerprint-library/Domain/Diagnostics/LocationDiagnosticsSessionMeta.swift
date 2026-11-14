import Foundation

/// 기록 시작 시 고르는 기기 자세. 같은 조건끼리 비교하기 위해 남긴다.
nonisolated enum LocationDiagnosticsPosture: String, Codable, CaseIterable, Sendable {
    case handViewing = "hand_viewing"
    case pocket
    case other

    var title: String {
        switch self {
        case .handViewing: "손에 들고 화면 보기"
        case .pocket: "주머니·가방"
        case .other: "기타"
        }
    }
}

/// 세션 조건. 기기 정보는 Client가 채운다.
nonisolated struct LocationDiagnosticsSessionMeta: Codable, Equatable, Sendable {
    var sessionID: String = ""
    var startedAt: Date
    var endedAt: Date?
    var posture: LocationDiagnosticsPosture
    var includesScreenRecording: Bool
    var includesMicrophone: Bool
    /// 검색창 `/test` 측정 모드로 자동 시작한 기록인지
    var isAutomatic: Bool? = nil
    var screenRecordingStartedAt: Date?
    var routePlanID: String
    var bookCount: Int
    var startsAtEntrance: Bool
    var usesManualOrigin: Bool
    var guidanceThresholds: [String: Double]
    var locationSettings: [String: String] = [:]
    var deviceModel: String?
    var systemVersion: String?
    var appVersion: String?
    var appBuild: String?
    var isLowPowerModeEnabled: Bool?
    var thermalState: String?
}

nonisolated enum LocationDiagnosticsCoding {
    /// 영상·로그와 시점을 맞추기 위해 밀리초까지 남긴다.
    static let dateFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func encoder(pretty: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(dateFormat))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = try? dateFormat.parse(text) { return date }
            if let date = try? Date.ISO8601FormatStyle().parse(text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "날짜 형식이 아니에요: \(text)")
        }
        return decoder
    }
}
