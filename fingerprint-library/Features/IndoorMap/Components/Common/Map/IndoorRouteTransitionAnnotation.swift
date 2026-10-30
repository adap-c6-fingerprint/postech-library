import MapKit
import UIKit

/// 층간 이동의 진입·출구를 지도 축척과 무관한 원형 배지로 표시한다.
final class IndoorRouteTransitionAnnotation: NSObject, MKAnnotation {
    let category: RouteEdgeCategory
    let coordinate: CLLocationCoordinate2D
    let isEntry: Bool

    init(change: RouteFloorChange, isEntry: Bool) {
        category = change.category
        coordinate = (isEntry ? change.fromCoordinate : change.toCoordinate).clCoordinate
        self.isEntry = isEntry
    }

    var title: String? {
        switch category {
        case .elevator: "엘리베이터"
        case .stairs: "계단"
        case .escalator: "에스컬레이터"
        case .ramp: "경사로"
        case .platformLift: "휠체어 리프트"
        case .walkway: "층 연결 통로"
        }
    }

    var subtitle: String? { isEntry ? "층간 이동 진입 지점" : "층간 이동 출구 지점" }

    var symbolName: String {
        switch category {
        case .elevator: "arrow.up.arrow.down.square"
        case .stairs: "stairs"
        case .escalator: "arrow.up.forward.and.arrow.down.backward"
        case .ramp, .platformLift: "figure.roll"
        case .walkway: "arrow.up.arrow.down"
        }
    }

    var markerImage: UIImage {
        let size = CGSize(width: 36, height: 36)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let circle = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1))
            UIColor.systemBlue.setFill()
            circle.fill()
            UIColor.white.setStroke()
            circle.lineWidth = 2
            circle.stroke()
            let configuration = UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
            guard let symbol = UIImage(systemName: symbolName, withConfiguration: configuration)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) else { return }
            let scale = min(22 / symbol.size.width, 22 / symbol.size.height)
            let glyphSize = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
            symbol.draw(in: CGRect(
                x: (size.width - glyphSize.width) / 2, y: (size.height - glyphSize.height) / 2,
                width: glyphSize.width, height: glyphSize.height))
        }
    }
}
