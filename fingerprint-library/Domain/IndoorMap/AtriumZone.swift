import Foundation

/// 도서관 중앙의 뚫린 공간(IMDF `opentobelow` unit) 근처인지 판단해, CLFloor 한 건의 신뢰도를 준다.
/// 이 근처에서는 다른 층 Wi-Fi가 섞여 CLFloor가 자주 틀린다.
/// v3 설계의 중앙 공간 경계와 관측 가중치를 사용한다.
nonisolated struct AtriumZone: Equatable, Sendable {
    /// 모든 층의 `opentobelow` 윤곽. 층을 가리지 않는다(층을 모르는 상황에서 쓰기 때문).
    var outlines: [IndoorMapGeometry]
    var edgeMeters = 1.5
    var nearTrust = 0.1

    init(outlines: [IndoorMapGeometry], edgeMeters: Double = 1.5, nearTrust: Double = 0.1) {
        self.outlines = outlines
        self.edgeMeters = edgeMeters
        self.nearTrust = nearTrust
    }

    init(map: IndoorMap) {
        self.init(outlines: map.features
            .filter { $0.kind == .unit && $0.category == "opentobelow" }
            .map(\.geometry))
    }

    /// 가장 가까운 윤곽까지의 거리(m). 윤곽 안이면 0. 좌표가 유효하지 않거나 윤곽이 없으면 nil.
    func distanceMeters(at coordinate: IndoorMapCoordinate) -> Double? {
        guard coordinate.isValid else { return nil }
        return outlines
            .map { $0.contains(coordinate) ? 0 : $0.distanceToBoundaryMeters(from: coordinate) }
            .min()
    }

    /// 윤곽 안이거나 윤곽에서 `edgeMeters` 이내면 `nearTrust`, 아니면 1.
    /// 좌표가 유효하지 않으면 근처로 본다(멀다고 확인할 수 없으므로).
    func trust(at coordinate: IndoorMapCoordinate) -> Double {
        guard coordinate.isValid else { return nearTrust }
        guard let distance = distanceMeters(at: coordinate) else { return 1 }  // 윤곽이 없으면 가중치 없음
        return distance <= edgeMeters ? nearTrust : 1
    }
}
