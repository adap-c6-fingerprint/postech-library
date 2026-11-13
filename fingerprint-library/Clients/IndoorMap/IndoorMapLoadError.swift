import Foundation

nonisolated enum IndoorMapLoadError: LocalizedError {
    case missingResource(String)
    case invalidData(file: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let path):
            "지도 리소스를 찾을 수 없습니다: \(path)"
        case .invalidData(let file, let reason):
            "지도 데이터를 읽을 수 없습니다 (\(file)): \(reason)"
        }
    }
}
