import Foundation

/// 화면 수명과 별도로 완료 이미지를 보관하고, URL별 진행 중 작업을 공유한다.
@MainActor
final class SharedImageLoader<Image: Sendable> {
    private final class CachedImage: NSObject {
        let image: Image

        init(_ image: Image) { self.image = image }
    }

    private struct Request {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<Image, Error>]
        var cancellation: Task<Void, Never>?
    }

    private let cache = NSCache<NSURL, CachedImage>()
    private var requests: [URL: Request] = [:]
    private let loadImage: @MainActor @Sendable (URL) async throws -> Image
    private let cost: (Image) -> Int
    private let cancellationDelay: Duration
    private let readLocalImage: (@MainActor (URL) -> Image?)?

    init(
        memoryLimit: Int = 32 * 1_024 * 1_024,
        countLimit: Int = 100,
        cancellationDelay: Duration = .milliseconds(250),
        readLocalImage: (@MainActor (URL) -> Image?)? = nil,
        cost: @escaping (Image) -> Int,
        loadImage: @escaping @MainActor @Sendable (URL) async throws -> Image
    ) {
        cache.totalCostLimit = memoryLimit
        cache.countLimit = countLimit
        self.cancellationDelay = cancellationDelay
        self.cost = cost
        self.loadImage = loadImage
        self.readLocalImage = readLocalImage
    }

    func cachedImage(for url: URL) -> Image? {
        if let image = cache.object(forKey: url as NSURL)?.image { return image }
        guard let image = readLocalImage?(url) else { return nil }
        cache.setObject(CachedImage(image), forKey: url as NSURL, cost: cost(image))
        return image
    }

    func image(for url: URL) async throws -> Image {
        try Task.checkCancellation()
        if let image = cachedImage(for: url) { return image }

        let waiterID = UUID()
        let image: Image = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                subscribe(continuation, id: waiterID, url: url)
            }
        } onCancel: {
            Task { @MainActor in
                self.unsubscribe(id: waiterID, url: url)
            }
        }
        try Task.checkCancellation()
        return image
    }

    func removeCachedImages() {
        cache.removeAllObjects()
    }

    /// 전체 목록을 내려받지 않고 다음 두 표지만 같은 파이프라인으로 준비한다.
    func prefetch(_ urls: [URL]) async {
        var seen: Set<URL> = []
        let targets = urls.filter { seen.insert($0).inserted }.prefix(2)
        await withTaskGroup(of: Void.self) { group in
            for url in targets {
                group.addTask { [self] in
                    _ = try? await image(for: url)
                }
            }
        }
    }

    private func subscribe(
        _ continuation: CheckedContinuation<Image, Error>,
        id: UUID,
        url: URL
    ) {
        if var request = requests[url] {
            request.cancellation?.cancel()
            request.cancellation = nil
            request.waiters[id] = continuation
            requests[url] = request
            return
        }

        let requestID = UUID()
        let task = Task { @MainActor in
            let result: Result<Image, Error>
            do {
                let image = try await loadImage(url)
                try Task.checkCancellation()
                result = .success(image)
            } catch {
                result = .failure(error)
            }
            complete(result, url: url, requestID: requestID)
        }
        requests[url] = Request(
            id: requestID, task: task, waiters: [id: continuation]
        )
    }

    private func complete(_ result: Result<Image, Error>, url: URL, requestID: UUID) {
        // 이전 작업이 늦게 끝나더라도 같은 URL의 새 작업을 제거하지 않는다.
        guard let request = requests[url], request.id == requestID else { return }
        requests[url] = nil
        request.cancellation?.cancel()
        if case let .success(image) = result {
            cache.setObject(CachedImage(image), forKey: url as NSURL, cost: cost(image))
        }
        for waiter in request.waiters.values {
            waiter.resume(with: result)
        }
    }

    private func unsubscribe(id: UUID, url: URL) {
        guard var request = requests[url],
              let waiter = request.waiters.removeValue(forKey: id) else { return }
        waiter.resume(throwing: CancellationError())
        if request.waiters.isEmpty {
            let requestID = request.id
            request.cancellation = Task { @MainActor in
                do { try await Task.sleep(for: cancellationDelay) }
                catch { return }
                guard let current = requests[url], current.id == requestID,
                      current.waiters.isEmpty else { return }
                requests[url] = nil
                current.task.cancel()
            }
        }
        requests[url] = request
    }
}
