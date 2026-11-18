//
//  DemoFixtureHTTPClient.swift
//  fingerprint-library
//
//  오프라인 시연(Demo 빌드)용 HTTP 응답 녹화·재생.
//  - 녹화: Debug 빌드를 `POBOOK_DEMO_RECORD_DIR` 환경 변수와 함께 실행하면 성공 응답을 그 폴더에 저장한다.
//  - 재생: Demo 빌드는 번들의 `DemoFixtures`에서만 응답을 찾고 네트워크에 접근하지 않는다.
//  인증 헤더는 키·파일 어디에도 저장하지 않는다.
//

import CryptoKit
import Foundation

nonisolated enum DemoFixtureKey {
    private static let relayHosts: Set<String> = Set(
        [APIRelayEnvironment.development, .production].compactMap { $0.baseURL.host()?.lowercased() }
    )

    /// 중계 서버의 개발·운영 호스트를 하나로 묶어, 녹화한 빌드와 재생하는 빌드의 환경이 달라도 같은 키가 되게 한다.
    static func make(for request: URLRequest) -> String? {
        guard
            let url = request.url,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let host = components.host?.lowercased()
        else { return nil }
        let origin = relayHosts.contains(host) ? "relay" : host
        let query = (components.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") }
            .sorted { $0 < $1 }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "&")
        return "\(request.httpMethod ?? "GET") \(origin)\(components.path)?\(query)"
    }

    static func fileName(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined() + ".bin"
    }
}

nonisolated struct DemoFixtureManifest: Codable, Equatable, Sendable {
    nonisolated struct Entry: Codable, Equatable, Sendable {
        let statusCode: Int
        let contentType: String?
        let file: String
    }

    static let fileName = "manifest.json"

    var entries: [String: Entry] = [:]
}

nonisolated struct DemoFixtureMissError: LocalizedError, Equatable {
    var errorDescription: String? { "오프라인 시연 버전에 포함되지 않은 정보예요." }
}

/// 재생용 응답 묶음. 번들 폴더를 처음 요청할 때 한 번만 읽는다.
nonisolated final class DemoFixtureStore: @unchecked Sendable {
    static let bundled = DemoFixtureStore(directory: Bundle.main.url(forResource: "DemoFixtures", withExtension: nil))

    private let directory: URL?
    private let lock = NSLock()
    private var manifest: DemoFixtureManifest?

    init(directory: URL?) {
        self.directory = directory
    }

    func response(for request: URLRequest) throws -> (Data, URLResponse) {
        guard
            let directory, let url = request.url,
            let key = DemoFixtureKey.make(for: request),
            let entry = loadManifest().entries[key],
            let data = try? Data(contentsOf: directory.appending(path: entry.file)),
            let response = HTTPURLResponse(
                url: url, statusCode: entry.statusCode, httpVersion: "HTTP/1.1",
                headerFields: entry.contentType.map { ["Content-Type": $0] }
            )
        else { throw DemoFixtureMissError() }
        return (data, response)
    }

    private func loadManifest() -> DemoFixtureManifest {
        lock.withLock {
            if let manifest { return manifest }
            let loaded = directory
                .flatMap { try? Data(contentsOf: $0.appending(path: DemoFixtureManifest.fileName)) }
                .flatMap { try? JSONDecoder().decode(DemoFixtureManifest.self, from: $0) }
                ?? DemoFixtureManifest()
            manifest = loaded
            return loaded
        }
    }
}

extension HTTPClient {
    static func demoReplay(_ store: DemoFixtureStore = .bundled) -> Self {
        Self(load: { request in try store.response(for: request) })
    }
}

#if DEBUG
/// 녹화 전용. 성공 응답만 저장하고, 같은 요청은 마지막 응답으로 덮어쓴다.
nonisolated final class DemoFixtureRecorder: @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()

    init(directory: URL) {
        self.directory = directory
    }

    func record(_ request: URLRequest, data: Data, response: URLResponse) {
        guard
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            let key = DemoFixtureKey.make(for: request)
        else { return }
        lock.withLock {
            let manifestURL = directory.appending(path: DemoFixtureManifest.fileName)
            var manifest = (try? Data(contentsOf: manifestURL))
                .flatMap { try? JSONDecoder().decode(DemoFixtureManifest.self, from: $0) } ?? DemoFixtureManifest()
            let file = DemoFixtureKey.fileName(for: key)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: directory.appending(path: file), options: .atomic)
                manifest.entries[key] = .init(
                    statusCode: http.statusCode,
                    contentType: http.value(forHTTPHeaderField: "Content-Type"),
                    file: file
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
            } catch {
                assertionFailure("Demo fixture recording failed: \(error)")
            }
        }
    }
}

extension HTTPClient {
    static func demoRecording(into directory: URL, session: URLSession = .shared) -> Self {
        let recorder = DemoFixtureRecorder(directory: directory)
        return Self(load: { request in
            let (data, response) = try await session.data(for: request)
            recorder.record(request, data: data, response: response)
            return (data, response)
        })
    }
}
#endif
