import Foundation

/// 실시간 안내 위치 품질 진단 기록의 한 줄(JSONL)이다. 실험 브랜치 전용.
nonisolated enum LocationDiagnosticsRecord: Equatable, Sendable {
    case location(LocationSample)
    case heading(HeadingSample)
    case guidance(GuidanceSample)
    case motion(MotionSample)
    case activity(ActivitySample)
    case marker(Marker)
    case event(Event)
    case route(RouteSnapshot)

    var time: Date {
        switch self {
        case let .location(value): value.receivedAt
        case let .heading(value): value.receivedAt
        case let .guidance(value): value.at
        case let .motion(value): value.at
        case let .activity(value): value.at
        case let .marker(value): value.at
        case let .event(value): value.at
        case let .route(value): value.at
        }
    }

    /// Core Location이 준 원본 측위값.
    nonisolated struct LocationSample: Codable, Equatable, Sendable {
        var receivedAt: Date
        var timestamp: Date
        var latitude: Double
        var longitude: Double
        var horizontalAccuracy: Double
        var verticalAccuracy: Double?
        var altitude: Double?
        var floorLevel: Int?
        var speed: Double?
        var speedAccuracy: Double?
        var course: Double?
        var courseAccuracy: Double?
        var isSimulatedBySoftware: Bool?
        var isProducedByAccessory: Bool?

        var coordinate: IndoorMapCoordinate { .init(latitude: latitude, longitude: longitude) }
    }

    nonisolated struct HeadingSample: Codable, Equatable, Sendable {
        var receivedAt: Date
        var timestamp: Date
        var trueHeading: Double
        var magneticHeading: Double
        var headingAccuracy: Double
    }

    /// 앱이 위치 1건을 처리한 결과와 실제로 화면에 그린 값.
    nonisolated struct GuidanceSample: Codable, Equatable, Sendable {
        var at: Date
        var positionTimestamp: Date?
        var stopIndex: Int
        /// on_route, degraded, lost, off_route, ambiguous_position, unknown_floor, inaccurate, stale, outside, floor_unselected, rerouting, unusable_position
        var quality: String
        var floorOrdinal: Int?
        var displayedLatitude: Double?
        var displayedLongitude: Double?
        var matchedLatitude: Double?
        var matchedLongitude: Double?
        var distanceToRoute: Double?
        var distanceAlongRoute: Double?
        var remainingMeters: Double?
        var stepIndex: Int?
        var maneuver: String?
        var instruction: String?
        var cameraRequestID: Int
        /// GuidanceTracker 상태: tracking, degraded, lost
        var trackingStatus: String? = nil
        /// 진행 거리 추정의 표준편차(m)
        var uncertaintyMeters: Double? = nil
    }

    nonisolated struct MotionSample: Codable, Equatable, Sendable {
        var at: Date
        var startDate: Date
        var endDate: Date
        var steps: Int
        var distance: Double?
        var cadence: Double?
    }

    nonisolated struct ActivitySample: Codable, Equatable, Sendable {
        var at: Date
        var startDate: Date
        var isStationary: Bool
        var isWalking: Bool
        var isRunning: Bool
        var isAutomotive: Bool
        var isCycling: Bool
        var isUnknown: Bool
        /// 0 낮음, 1 보통, 2 높음
        var confidence: Int
    }

    nonisolated struct Marker: Codable, Equatable, Sendable {
        nonisolated enum Kind: String, Codable, Sendable {
            /// 지도 십자선으로 지정한 실제 위치
            case checkpoint
            /// 목적지 서가 앞이라고 확인한 실제 위치
            case destination
            /// 체감상 튄 시점
            case jump
        }

        var at: Date
        var kind: Kind
        var latitude: Double?
        var longitude: Double?
        var floorOrdinal: Int?
        var label: String?

        var coordinate: IndoorMapCoordinate? {
            guard let latitude, let longitude else { return nil }
            return .init(latitude: latitude, longitude: longitude)
        }
    }

    nonisolated struct Event: Codable, Equatable, Sendable {
        var at: Date
        var name: String
        var detail: [String: String] = [:]
    }

    /// 재생·시각화에 쓰는 안내 경로. 경로가 바뀔 때마다 새로 남긴다.
    nonisolated struct RouteSnapshot: Codable, Equatable, Sendable {
        nonisolated struct Segment: Codable, Equatable, Sendable {
            var floorOrdinal: Int
            /// [위도, 경도]
            var coordinates: [[Double]]
        }

        var at: Date
        var stopIndex: Int
        var reason: String
        var segments: [Segment]
        var destinationLatitude: Double
        var destinationLongitude: Double
        var destinationFloorOrdinal: Int
    }
}

extension LocationDiagnosticsRecord: Codable {
    private enum TypeKey: String, CodingKey { case type }
    private enum Kind: String, Codable {
        case location, heading, guidance, motion, activity, marker, event, route
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .location: self = .location(try LocationSample(from: decoder))
        case .heading: self = .heading(try HeadingSample(from: decoder))
        case .guidance: self = .guidance(try GuidanceSample(from: decoder))
        case .motion: self = .motion(try MotionSample(from: decoder))
        case .activity: self = .activity(try ActivitySample(from: decoder))
        case .marker: self = .marker(try Marker(from: decoder))
        case .event: self = .event(try Event(from: decoder))
        case .route: self = .route(try RouteSnapshot(from: decoder))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        switch self {
        case let .location(value):
            try container.encode(Kind.location, forKey: .type)
            try value.encode(to: encoder)
        case let .heading(value):
            try container.encode(Kind.heading, forKey: .type)
            try value.encode(to: encoder)
        case let .guidance(value):
            try container.encode(Kind.guidance, forKey: .type)
            try value.encode(to: encoder)
        case let .motion(value):
            try container.encode(Kind.motion, forKey: .type)
            try value.encode(to: encoder)
        case let .activity(value):
            try container.encode(Kind.activity, forKey: .type)
            try value.encode(to: encoder)
        case let .marker(value):
            try container.encode(Kind.marker, forKey: .type)
            try value.encode(to: encoder)
        case let .event(value):
            try container.encode(Kind.event, forKey: .type)
            try value.encode(to: encoder)
        case let .route(value):
            try container.encode(Kind.route, forKey: .type)
            try value.encode(to: encoder)
        }
    }
}

/// 연속된 두 원본 위치 사이의 이동량. 보행 속도를 크게 넘으면 튐으로 본다.
nonisolated struct LocationJump: Equatable, Sendable {
    static let walkingSpeedLimit = 2.5
    static let minimumJumpMeters = 1.5

    let meters: Double
    let seconds: Double
    var metersPerSecond: Double? { seconds > 0 ? meters / seconds : nil }
    var isJump: Bool {
        guard meters >= Self.minimumJumpMeters else { return false }
        guard let speed = metersPerSecond else { return true }
        return speed > Self.walkingSpeedLimit
    }

    init(meters: Double, seconds: Double) {
        self.meters = meters
        self.seconds = seconds
    }

    init?(from previous: IndoorPosition?, to current: IndoorPosition) {
        guard let previous, previous.coordinate.isValid, current.coordinate.isValid,
              current.timestamp > previous.timestamp else { return nil }
        self.init(meters: RoutingGeometry.distanceMeters(from: previous.coordinate, to: current.coordinate),
                  seconds: current.timestamp.timeIntervalSince(previous.timestamp))
    }
}
