import MapKit

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
