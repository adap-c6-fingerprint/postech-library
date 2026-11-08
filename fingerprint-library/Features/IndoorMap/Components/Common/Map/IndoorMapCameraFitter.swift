import MapKit
import UIKit

/// 회전 각도를 유지하면서 시트·안내 UI에 가리지 않는 영역에 맞는 평면 카메라를 계산한다.
@MainActor
enum IndoorMapCameraFitter {
    static func camera(fitting coordinates: [IndoorMapCoordinate], minimumSpanMeters: Double, in view: MKMapView,
                       padding: UIEdgeInsets) -> MKMapCamera? {
        let viewport = view.bounds.inset(by: padding)
        guard viewport.width > 0, viewport.height > 0,
              minimumSpanMeters.isFinite, minimumSpanMeters > 0,
              coordinates.allSatisfy(\.isValid), let first = coordinates.first else { return nil }
        let reference = MKMapPoint(first.clCoordinate)
        let angle = view.camera.heading * .pi / 180
        let cosine = cos(angle), sine = sin(angle)
        let points = coordinates.map { coordinate -> CGPoint in
            let point = MKMapPoint(coordinate.clCoordinate)
            let x = point.x - reference.x, y = point.y - reference.y
            return .init(x: cosine * x + sine * y, y: -sine * x + cosine * y)
        }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return nil }
        let pointsPerMeter = MKMapPointsPerMeterAtLatitude(first.latitude)
        let margin = 2 * pointsPerMeter
        // 최소 폭을 화면 비율에 맞춰 적용해 가로 화면에서도 접근에 따라 확대한다.
        let width = max(maxX - minX + margin * 2, minimumSpanMeters * pointsPerMeter)
        let height = max(maxY - minY + margin * 2,
                         minimumSpanMeters * pointsPerMeter * viewport.height / viewport.width)
        let scale = max(width / viewport.width, height / viewport.height)

        let currentCenter = MKMapPoint(view.centerCoordinate)
        let currentPointsPerMeter = MKMapPointsPerMeterAtLatitude(view.centerCoordinate.latitude)
        let from = view.convert(view.centerCoordinate, toPointTo: view)
        let to = view.convert(MKMapPoint(x: currentCenter.x + currentPointsPerMeter * 10,
                                        y: currentCenter.y).coordinate, toPointTo: view)
        let pixels = hypot(to.x - from.x, to.y - from.y)
        guard pixels.isFinite, pixels > 0, scale.isFinite, scale > 0 else { return nil }
        let currentMetersPerPixel = 10 / pixels
        let targetMetersPerPixel = scale / pointsPerMeter

        let x = (minX + maxX) / 2 + (from.x - viewport.midX) * scale
        let y = (minY + maxY) / 2 + (from.y - viewport.midY) * scale
        let center = MKMapPoint(x: reference.x + cosine * x - sine * y,
                                y: reference.y + sine * x + cosine * y)
        let camera = view.camera.copy() as! MKMapCamera
        camera.pitch = 0
        camera.centerCoordinate = center.coordinate
        camera.centerCoordinateDistance *= targetMetersPerPixel / currentMetersPerPixel
        guard camera.centerCoordinateDistance.isFinite, camera.centerCoordinateDistance > 0 else { return nil }
        return camera
    }
}
