import MapKit
import UIKit

/// 실내 지도 도형 하나를 그리는 색·선 두께. 같은 값이면 하나의 overlay로 묶을 수 있다.
struct IndoorOverlayStyle: Hashable {
    var fillColor: UIColor?
    var strokeColor: UIColor?
    var lineWidth: CGFloat = 0

    func apply(to renderer: MKOverlayPathRenderer) {
        renderer.fillColor = fillColor
        renderer.strokeColor = strokeColor
        renderer.lineWidth = lineWidth
    }
}

/// 그리기 순서를 유지하면서 같은 스타일이 이어지는 도형을 `MKMultiPolygon`·`MKMultiPolyline`으로 묶는다.
/// MapKit은 overlay를 추가할 때마다 고정 비용이 들어서, 층 도형 수백 개를 따로 추가하면 화면 진입이 멈춘다.
struct IndoorOverlayBatcher {
    private var batches: [(overlay: any MKOverlay, style: IndoorOverlayStyle)] = []
    private var currentStyle: IndoorOverlayStyle?
    private var polygons: [MKPolygon] = []
    private var polylines: [MKPolyline] = []

    mutating func append(_ geometry: IndoorMapGeometry, style: IndoorOverlayStyle) {
        let overlays = MapKitGeometry.overlays(for: geometry)
        guard !overlays.isEmpty else { return }
        if style != currentStyle {
            flush()
            currentStyle = style
        }
        for overlay in overlays {
            if let polygon = overlay as? MKPolygon {
                polygons.append(polygon)
            } else if let polyline = overlay as? MKPolyline {
                polylines.append(polyline)
            }
        }
    }

    mutating func finish() -> [(overlay: any MKOverlay, style: IndoorOverlayStyle)] {
        flush()
        return batches
    }

    private mutating func flush() {
        guard let currentStyle else { return }
        if !polygons.isEmpty {
            batches.append((polygons.count == 1 ? polygons[0] : MKMultiPolygon(polygons), currentStyle))
        }
        if !polylines.isEmpty {
            batches.append((polylines.count == 1 ? polylines[0] : MKMultiPolyline(polylines), currentStyle))
        }
        polygons.removeAll(keepingCapacity: true)
        polylines.removeAll(keepingCapacity: true)
    }
}
