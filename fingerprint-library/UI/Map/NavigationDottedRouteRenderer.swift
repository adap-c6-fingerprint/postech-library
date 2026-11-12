import MapKit

/// 점의 지름과 간격을 화면 포인트로 유지한다. 지도 좌표계에서는 줌 배율의 역수로 보정한다.
nonisolated final class NavigationDottedRouteRenderer: MKPolylineRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard zoomScale.isFinite, zoomScale > 0, let path = path, let color = strokeColor else { return }
        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth / zoomScale)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let pattern = (lineDashPattern ?? [0, 9]).map { CGFloat(truncating: $0) / zoomScale }
        context.setLineDash(phase: lineDashPhase / zoomScale, lengths: pattern)
        context.strokePath()
        context.restoreGState()
    }
}
