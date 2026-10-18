#if DEBUG && targetEnvironment(simulator)
import Foundation
import Network

nonisolated enum IndoorSimulationLocationProvider {
    static let defaultPort: UInt16 = 57_575
    private static let queue = DispatchQueue(label: "postech-library.indoor-simulation", qos: .userInitiated)

    static func events(port: UInt16 = defaultPort) -> AsyncStream<IndoorLocationEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(10)) { continuation in
            let task = Task { await run(port: port, continuation: continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    @concurrent
    private static func run(port: UInt16, continuation: AsyncStream<IndoorLocationEvent>.Continuation) async {
        guard let port = NWEndpoint.Port(rawValue: port) else { continuation.finish(); return }
        // 합성 위치 공급의 사용 가능 상태이며 시스템 위치 권한을 요청하지 않는다.
        continuation.yield(.authorization(.authorized(precise: true)))
        continuation.yield(.unavailable("시뮬레이터 연결을 기다리고 있어요."))
        while !Task.isCancelled {
            let connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
            connection.start(queue: queue)
            do {
                try await consume(connection, continuation: continuation)
            } catch {
                if !Task.isCancelled {
                    continuation.yield(.unavailable((error as? IndoorSimulationError)?.localizedDescription
                        ?? "시뮬레이터에 연결하지 못했어요. 다시 연결하고 있어요."))
                }
            }
            connection.cancel()
            do { try await Task.sleep(for: .seconds(1)) } catch { break }
        }
        continuation.finish()
    }

    private static func consume(_ connection: NWConnection,
                                continuation: AsyncStream<IndoorLocationEvent>.Continuation) async throws {
        var decoder = IndoorSimulationStreamDecoder()
        var sessionID: UUID?
        var sequence: UInt64?
        while !Task.isCancelled {
            let (data, complete) = try await receive(connection)
            for frame in try decoder.append(data) {
                if sessionID == frame.sessionID, let sequence, frame.sequenceNumber <= sequence { continue }
                let position = try frame.position(at: Date())
                sessionID = frame.sessionID
                sequence = frame.sequenceNumber
                continuation.yield(.position(position))
            }
            if complete { throw IndoorSimulationError.disconnected }
        }
        throw CancellationError()
    }

    private struct Chunk: Sendable { let data: Data; let complete: Bool }

    private static func receive(_ connection: NWConnection) async throws -> (Data, Bool) {
        let chunk = try await withThrowingTaskGroup(of: Chunk.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, complete, error in
                            if let error { continuation.resume(throwing: error) }
                            else { continuation.resume(returning: Chunk(data: data ?? Data(), complete: complete)) }
                        }
                    }
                } onCancel: { connection.cancel() }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                throw IndoorSimulationError.timedOut
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
        return (chunk.data, chunk.complete)
    }
}
#endif
