import MapKit
import UIKit

/// 원본 위치 링과 방향 부채꼴을 사용한다. 링 중심은 항상 실제 지도 좌표에 고정한다.
@MainActor
final class HomeUserLocationAnnotationView: MKAnnotationView {
    private let dotView = UIImageView(image: UIImage(named: "MapUserLocation")?.withRenderingMode(.alwaysOriginal))
    private let headingView = UIImageView(image: UIImage(named: "MapUserHeading")?.withRenderingMode(.alwaysOriginal))

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    private func configureViews() {
        bounds = CGRect(x: 0, y: 0, width: 25, height: 25)
        centerOffset = .zero
        clipsToBounds = false
        displayPriority = .required
        collisionMode = .circle
        isEnabled = false
        isAccessibilityElement = true
        dotView.contentMode = .scaleAspectFit
        dotView.accessibilityIdentifier = "user-location-dot-image"
        headingView.contentMode = .scaleAspectFit
        headingView.accessibilityIdentifier = "user-location-heading-image"
        headingView.bounds = CGRect(x: 0, y: 0, width: 49, height: 39)
        headingView.layer.anchorPoint = CGPoint(x: 0, y: 1)
        headingView.isHidden = true
        addSubview(headingView)
        addSubview(dotView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dotView.frame = bounds
        headingView.layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    /// 방향은 북쪽 기준 시계 방향 각도다. 지도 회전과 원본 이미지의 북동쪽 방향을 보정한다.
    func configure(headingDegrees: Double?, mapHeading: Double) {
        guard let headingDegrees, headingDegrees.isFinite, (0..<360).contains(headingDegrees),
              mapHeading.isFinite else {
            headingView.isHidden = true
            return
        }
        headingView.isHidden = false
        let angle = (headingDegrees - mapHeading) * .pi / 180 - .pi / 4
        headingView.transform = CGAffineTransform(rotationAngle: angle)
    }
}
