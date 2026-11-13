import os

/// 책 상세 지도 성능 측정용 임시 signpost. Instruments의 Points of Interest에 표시된다.
nonisolated enum MapPerformanceSignpost {
    static let signposter = OSSignposter(subsystem: "com.youngmin.fingerprint-library", category: .pointsOfInterest)
}
