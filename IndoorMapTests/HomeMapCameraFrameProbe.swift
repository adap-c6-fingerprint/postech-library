import MapKit
import UIKit

@MainActor
/// 동일한 카메라 경로에서 메인 스레드의 표시 콜백 간격을 비교한다. GPU의 실제 화면 표시율 측정은 아니다.
final class HomeMapCameraFrameProbe: NSObject {
    private let map: MKMapView
    private let initialCamera: MKMapCamera
    private var link: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var previousTime: CFTimeInterval?
    private var gaps: [Double] = []

    init(map: MKMapView) {
        self.map = map
        initialCamera = map.camera.copy() as! MKMapCamera
    }

    func start() {
        startTime = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        self.link = link
        link.add(to: .main, forMode: .common)
    }

    func stop() {
        link?.invalidate()
        link = nil
        map.setCamera(initialCamera, animated: false)
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        if let previousTime { gaps.append(now - previousTime) }
        previousTime = now
        let elapsed = now - startTime
        let camera = initialCamera.copy() as! MKMapCamera
        camera.centerCoordinate.latitude += sin(elapsed * .pi) * 0.00004
        camera.centerCoordinate.longitude += cos(elapsed * .pi) * 0.00006
        camera.centerCoordinateDistance *= 1 + sin(elapsed * .pi) * 0.12
        map.setCamera(camera, animated: false)
    }

    func report() -> String {
        let sorted = gaps.sorted()
        guard !sorted.isEmpty else { return "no_frames" }
        let total = gaps.reduce(0, +)
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        return "callbacks=\(gaps.count) callback_fps=\(Double(gaps.count) / total) p95_ms=\(p95 * 1000) max_ms=\(sorted.last! * 1000) gaps_over_33ms=\(gaps.filter { $0 > 1.0 / 30 }.count)"
    }
}
