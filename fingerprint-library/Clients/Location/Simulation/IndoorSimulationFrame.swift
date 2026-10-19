#if DEBUG && targetEnvironment(simulator)
import Foundation

/// IndoorPositioningSimulator의 schema 1 중 위치 QA에 필요한 필드만 읽는다.
/// Date는 producer의 기본 JSONEncoder와 같은 2001-01-01 기준 초다.
nonisolated struct IndoorSimulationFrame: Decodable, Sendable {
    struct Device: Decodable, Sendable {
        struct Position: Decodable, Sendable {
            struct Coordinate: Decodable, Sendable {
                let latitude: Double
                let longitude: Double
            }
            let coordinate: Coordinate
            let levelOrdinal: Int
        }
        let position: Position
    }

    let schemaVersion: Int
    let sessionID: UUID
    let sequenceNumber: UInt64
    let generatedAt: Date
    let positioningMode: String?
    let device: Device

    func position(at now: Date) throws -> IndoorPosition {
        guard schemaVersion == 1 else { throw IndoorSimulationError.unsupportedSchema }
        guard positioningMode == "groundTruth" else { throw IndoorSimulationError.radioMode }
        let coordinate = device.position.coordinate
        let position = IndoorPosition(
            coordinate: .init(latitude: coordinate.latitude, longitude: coordinate.longitude),
            floorOrdinal: device.position.levelOrdinal, horizontalAccuracy: 0,
            timestamp: generatedAt, source: .simulation
        )
        guard position.isRecent(at: now) else { throw IndoorSimulationError.invalidPosition }
        return position
    }
}

/// TCP는 프레임 경계를 보존하지 않으므로 분할·합쳐진 수신을 모두 처리한다.
nonisolated struct IndoorSimulationStreamDecoder: Sendable {
    static let maximumFrameLength = 1_048_576
    private var buffer = Data()

    mutating func append(_ data: Data) throws -> [IndoorSimulationFrame] {
        buffer.append(data)
        var frames: [IndoorSimulationFrame] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            guard (1...Self.maximumFrameLength).contains(length) else {
                throw IndoorSimulationError.invalidFrameLength
            }
            guard buffer.count >= 4 + length else { break }
            let body = Data(buffer.dropFirst(4).prefix(length))
            buffer.removeFirst(4 + length)
            frames.append(try JSONDecoder().decode(IndoorSimulationFrame.self, from: body))
        }
        return frames
    }
}

nonisolated enum IndoorSimulationError: Error, LocalizedError {
    case unsupportedSchema, radioMode, invalidPosition, invalidFrameLength, disconnected, timedOut

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema: "지원하지 않는 시뮬레이터 데이터 버전입니다."
        case .radioMode: "시뮬레이터의 ‘Wi-Fi 위치 기반 측위’를 꺼서 길찾기 QA 모드로 전환해주세요."
        case .invalidPosition: "시뮬레이터 위치가 유효하지 않거나 오래되었습니다."
        case .invalidFrameLength: "시뮬레이터 데이터 크기가 올바르지 않습니다."
        case .disconnected: "시뮬레이터 연결이 끊겼습니다. 다시 연결하고 있어요."
        case .timedOut: "시뮬레이터 위치 수신을 기다리고 있어요."
        }
    }
}
#endif
