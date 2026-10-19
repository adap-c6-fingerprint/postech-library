#if DEBUG && targetEnvironment(simulator)
import Foundation
import Network
import Testing
@testable import fingerprint_library

enum SimulationTestFrame {
    static let session = UUID(uuidString: "C5000000-0000-4000-8000-000000000001")!

    static func body(sequence: UInt64 = 1, floor: Int = 4, latitude: Double = 36.001,
                     session: UUID = session, mode: String = "groundTruth", schema: Int = 1,
                     date: Date = IndoorMapTestData.now) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "schemaVersion": schema, "sessionID": session.uuidString, "sequenceNumber": sequence,
            "generatedAt": date.timeIntervalSinceReferenceDate, "positioningMode": mode,
            "device": ["position": ["coordinate": ["latitude": latitude, "longitude": 129.001],
                                      "levelOrdinal": floor],
                       "headingDegrees": 90, "walking": true, "speedMetersPerSecond": 1.125],
            "wifi": [], "bluetooth": [], "motion": ["timestamp": 0]
        ], options: [.sortedKeys])
    }

    static func packet(_ body: Data) -> Data {
        var length = UInt32(body.count).bigEndian
        var result = Data(bytes: &length, count: 4)
        result.append(body)
        return result
    }
}

struct IndoorSimulationFrameTests {
    @Test("기존 producer의 Date·좌표·음수 층을 그대로 읽고 합성 위치로 구분한다")
    func decodesProducerContract() throws {
        let frame = try JSONDecoder().decode(IndoorSimulationFrame.self,
                                            from: SimulationTestFrame.body(floor: -1))
        let position = try frame.position(at: IndoorMapTestData.now)
        #expect(position.source == .simulation)
        #expect(position.floorOrdinal == -1)
        #expect(position.coordinate == IndoorMapTestData.point)
        #expect(position.timestamp == IndoorMapTestData.now)
        #expect(position.horizontalAccuracy == 0)
    }

    @Test("TCP의 잘린 헤더·본문과 합쳐진 여러 프레임을 복원한다")
    func fragmentedAndCoalescedFrames() throws {
        var decoder = IndoorSimulationStreamDecoder()
        let first = SimulationTestFrame.packet(try SimulationTestFrame.body(sequence: 1))
        let second = SimulationTestFrame.packet(try SimulationTestFrame.body(sequence: 2))
        #expect(try decoder.append(Data(first.prefix(2))).isEmpty)
        #expect(try decoder.append(Data(first.dropFirst(2).prefix(17))).isEmpty)
        let frames = try decoder.append(Data(first.dropFirst(19)) + second)
        #expect(frames.map(\.sequenceNumber) == [1, 2])
        #expect(try decoder.append(Data()).isEmpty)
    }

    @Test("0·과대 길이는 본문을 기다리거나 할당하지 않고 거부한다", arguments: [UInt32(0), 1_048_577, .max])
    func invalidLengths(_ length: UInt32) {
        var value = length.bigEndian
        let header = Data(bytes: &value, count: 4)
        var decoder = IndoorSimulationStreamDecoder()
        #expect(throws: IndoorSimulationError.self) { try decoder.append(header) }
    }

    @Test("지원하지 않는 버전·radio 모드·오래된 위치·유효하지 않은 좌표를 수용하지 않는다")
    func invalidPositions() throws {
        let bodies = try [
            SimulationTestFrame.body(mode: "radioBased"),
            SimulationTestFrame.body(schema: 2),
            SimulationTestFrame.body(date: IndoorMapTestData.now.addingTimeInterval(-31)),
            SimulationTestFrame.body(date: IndoorMapTestData.now.addingTimeInterval(6)),
            SimulationTestFrame.body(latitude: 91)
        ]
        for body in bodies {
            let frame = try JSONDecoder().decode(IndoorSimulationFrame.self, from: body)
            #expect(throws: IndoorSimulationError.self) { try frame.position(at: IndoorMapTestData.now) }
        }
    }
}

extension IndoorMapSerialTests {
    @MainActor
    struct IndoorSimulationTransportTests {
        @Test("실제 TCP로 분할 프레임·중복 무시·연결 해제·새 세션 재연결과 취소를 검증한다")
        func transportLifecycle() async throws {
            let server = try SimulationTCPTestServer()
            let port = try await server.start()
            defer { server.stop() }
            server.onConnection = { connection, count in
                Task {
                    do {
                        if count == 1 {
                            let first = SimulationTestFrame.packet(try SimulationTestFrame.body(sequence: 2, date: Date()))
                            try await server.send(Data(first.prefix(2)), to: connection)
                            let older = SimulationTestFrame.packet(try SimulationTestFrame.body(sequence: 1, latitude: 37, date: Date()))
                            let next = SimulationTestFrame.packet(try SimulationTestFrame.body(sequence: 3, latitude: 36.002, date: Date()))
                            try await server.send(Data(first.dropFirst(2)) + older + next, to: connection)
                        } else {
                            let body = try SimulationTestFrame.body(sequence: 0, floor: 0, latitude: 36.003,
                                session: UUID(), date: Date())
                            try await server.send(SimulationTestFrame.packet(body), to: connection)
                        }
                    } catch { Issue.record(error) }
                }
            }

            let events = try await withThrowingTaskGroup(of: [IndoorLocationEvent].self) { group in
                group.addTask {
                    var events: [IndoorLocationEvent] = []
                    var positions = 0
                    for await event in IndoorSimulationLocationProvider.events(port: port) {
                        events.append(event)
                        if case .position = event {
                            positions += 1
                            if positions == 2 { await server.disconnectClients() }
                            if positions == 3 { return events }
                        }
                    }
                    return events
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(8))
                    throw IndoorSimulationError.timedOut
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
            let positions = events.compactMap { event -> IndoorPosition? in
                if case .position(let position) = event { position } else { nil }
            }
            #expect(positions.map { $0.coordinate.latitude } == [36.001, 36.002, 36.003])
            #expect(positions.map(\.floorOrdinal) == [4, 4, 0])
            #expect(positions.allSatisfy { $0.source == .simulation })
            #expect(events.contains(.temporarilyUnavailable("시뮬레이터 연결을 기다리고 있어요.")))
            #expect(events.contains(.unavailable(IndoorSimulationError.disconnected.localizedDescription)))
            #expect(server.connectionCount == 2)
            // 소비자가 종료되면 AsyncStream의 termination이 실제 연결도 취소한다.
            for _ in 0..<100 where server.activeConnections > 0 {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(server.activeConnections == 0)
        }
    }
}

@MainActor
private final class SimulationTCPTestServer {
    private let listener: NWListener
    private var connections: [UUID: NWConnection] = [:]
    private var readyContinuation: CheckedContinuation<UInt16, Error>?
    private(set) var connectionCount = 0
    var activeConnections: Int { connections.count }
    var onConnection: ((NWConnection, Int) -> Void)?

    init() throws { listener = try NWListener(using: .tcp, on: .any) }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, let continuation = self.readyContinuation else { return }
                    if case .ready = state, let port = self.listener.port {
                        self.readyContinuation = nil
                        continuation.resume(returning: port.rawValue)
                    } else if case .failed(let error) = state {
                        self.readyContinuation = nil
                        continuation.resume(throwing: error)
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.start(queue: .main)
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = UUID()
        connections[id] = connection
        connectionCount += 1
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .cancelled, .failed: self?.connections[id] = nil
                default: break
                }
            }
        }
        connection.start(queue: .main)
        // EOF를 감지해 소비자의 취소를 서버에서도 확인한다.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, complete, error in
            if complete || error != nil { connection.cancel() }
        }
        onConnection?(connection, connectionCount)
    }

    func send(_ data: Data, to connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }

    func disconnectClients() { connections.values.forEach { $0.cancel() }; connections.removeAll() }
    func stop() { disconnectClients(); listener.cancel() }
}
#endif
