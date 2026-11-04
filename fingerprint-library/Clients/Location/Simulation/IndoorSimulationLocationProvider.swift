#if DEBUG
import Foundation
import Network

nonisolated struct IndoorSimulationConfiguration: Equatable, Sendable {
    let host: String?
    let port: UInt16
    static let serviceType = "_indoor-sim._tcp"

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    static func usesSimulation(environment: [String: String], isSimulator: Bool) -> Bool {
        switch environment["INDOOR_POSITION_SOURCE"] {
        case "simulation": true
        case "live": false
        default: isSimulator
        }
    }

    static func connection(environment: [String: String], isSimulator: Bool) throws -> Self {
        let host = environment["INDOOR_SIMULATOR_HOST"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let host, host.isEmpty { throw IndoorSimulationError.invalidConfiguration }
        let port: UInt16
        if let value = environment["INDOOR_SIMULATOR_PORT"] {
            guard let parsed = UInt16(value), parsed > 0 else {
                throw IndoorSimulationError.invalidConfiguration
            }
            port = parsed
        } else {
            port = IndoorSimulationLocationProvider.defaultPort
        }
        return Self(host: host ?? (isSimulator ? "127.0.0.1" : nil), port: port)
    }
}

nonisolated enum IndoorSimulationLocationProvider {
    static let defaultPort: UInt16 = 57_575
    private static let queue = DispatchQueue(label: "postech-library.indoor-simulation", qos: .userInitiated)

    static func events() -> AsyncStream<IndoorLocationEvent> {
        do {
            let configuration = try IndoorSimulationConfiguration.connection(
                environment: ProcessInfo.processInfo.environment,
                isSimulator: IndoorSimulationConfiguration.isSimulator
            )
            return events(host: configuration.host, port: configuration.port)
        } catch {
            return AsyncStream { continuation in
                continuation.yield(.unavailable(error.localizedDescription))
                continuation.finish()
            }
        }
    }

    static func events(host: String? = "127.0.0.1", port: UInt16,
                       controllerName: String? = nil) -> AsyncStream<IndoorLocationEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(10)) { continuation in
            let task = Task { await run(host: host, port: port, controllerName: controllerName, continuation: continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    @concurrent
    private static func run(host: String?, port: UInt16, controllerName: String?,
                            continuation: AsyncStream<IndoorLocationEvent>.Continuation) async {
        guard let port = NWEndpoint.Port(rawValue: port) else { continuation.finish(); return }
        // 합성 위치 공급의 사용 가능 상태이며 시스템 위치 권한을 요청하지 않는다.
        continuation.yield(.authorization(.authorized(precise: true)))
        continuation.yield(.temporarilyUnavailable("시뮬레이터 연결을 기다리고 있어요."))
        while !Task.isCancelled {
            do {
                let endpoint = try await endpoint(host: host, port: port, controllerName: controllerName)
                try Task.checkCancellation()
                let connection = NWConnection(to: endpoint, using: .tcp)
                defer { connection.cancel() }
                connection.start(queue: queue)
                try await consume(connection, continuation: continuation)
            } catch {
                if !Task.isCancelled {
                    continuation.yield(.unavailable((error as? IndoorSimulationError)?.localizedDescription
                        ?? "시뮬레이터에 연결하지 못했어요. 다시 연결하고 있어요."))
                }
            }
            do { try await Task.sleep(for: .seconds(1)) } catch { break }
        }
        continuation.finish()
    }

    /// Browse anew after a disconnect so a restarted Mac or changed address is discovered again.
    private static func endpoint(host: String?, port: NWEndpoint.Port, controllerName: String?) async throws -> NWEndpoint {
        if let host { return .hostPort(host: NWEndpoint.Host(host), port: port) }
        let browser = NWBrowser(
            for: .bonjour(type: IndoorSimulationConfiguration.serviceType, domain: nil), using: .tcp
        )
        let results = AsyncThrowingStream<NWEndpoint, Error> { continuation in
            browser.browseResultsChangedHandler = { results, _ in
                let matches = results.filter { result in
                    guard let controllerName else { return true }
                    guard case .service(let name, _, _, _) = result.endpoint else { return false }
                    return name == controllerName
                }
                guard !matches.isEmpty else { return }
                // Choosing an arbitrary controller could move the user on the wrong map.
                guard matches.count == 1, let result = matches.first else {
                    continuation.finish(throwing: IndoorSimulationError.multipleControllers)
                    return
                }
                continuation.yield(result.endpoint)
                continuation.finish()
            }
            browser.stateUpdateHandler = { state in
                switch state {
                case .failed(let error), .waiting(let error):
                    continuation.finish(throwing: error)
                case .cancelled:
                    continuation.finish()
                default: break
                }
            }
            continuation.onTermination = { _ in browser.cancel() }
            browser.start(queue: queue)
        }
        for try await result in results {
            try Task.checkCancellation()
            return result
        }
        throw CancellationError()
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
