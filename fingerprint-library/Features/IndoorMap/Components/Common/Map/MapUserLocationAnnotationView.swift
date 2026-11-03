import MapKit
import UIKit

/// 홈과 길안내에서 같은 위치 에셋을 쓰고 헤드만 실제 좌표 주위에서 회전시킨다.
@MainActor
final class MapUserLocationAnnotationView: MKAnnotationView {
    private let dotView = UIImageView(image: UIImage(named: "MapUserLocation")?.withRenderingMode(.alwaysOriginal))
    private let headingView = UIImageView(image: UIImage(named: "MapUserHeading")?.withRenderingMode(.alwaysOriginal))
    private let headingContainer = UIView()
    private let haloView = UIView()

    // 테두리를 포함한 원본 에셋의 표시 크기다.
    private static let dotArtworkDiameter: CGFloat = 17
    private static let headingSize = CGSize(width: 15.89314, height: 12.36133)
    private static let headingGap: CGFloat = 2

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    private func configureViews() {
        bounds = CGRect(x: 0, y: 0, width: 32, height: 32)
        centerOffset = .zero
        clipsToBounds = false
        displayPriority = .required
        collisionMode = .circle
        isEnabled = false
        isAccessibilityElement = true
        dotView.contentMode = .scaleAspectFit
        dotView.accessibilityIdentifier = "user-location-dot-image"
        haloView.backgroundColor = .clear
        // 지정한 원형 경로를 흐리게 그린다. 화면 safe area와 무관하게 원 중심에 고정된다.
        haloView.layer.shadowColor = UIColor(red: 0.87, green: 0.96, blue: 0.24, alpha: 1).cgColor
        haloView.layer.shadowOpacity = 0.3
        haloView.layer.shadowRadius = 1.65517
        haloView.layer.shadowOffset = .zero
        haloView.clipsToBounds = false
        haloView.isUserInteractionEnabled = false
        haloView.accessibilityIdentifier = "user-location-halo"
        headingContainer.isUserInteractionEnabled = false
        headingContainer.accessibilityIdentifier = "user-location-heading-container"
        headingView.accessibilityIdentifier = "user-location-heading-image"
        headingView.bounds = CGRect(origin: .zero, size: Self.headingSize)
        headingView.contentMode = .scaleAspectFit
        headingView.isUserInteractionEnabled = false
        headingContainer.isHidden = true
        addSubview(haloView)
        addSubview(headingContainer)
        headingContainer.addSubview(headingView)
        addSubview(dotView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        haloView.frame = bounds
        haloView.layer.shadowPath = UIBezierPath(ovalIn: haloView.bounds).cgPath
        dotView.bounds = CGRect(x: 0, y: 0, width: Self.dotArtworkDiameter, height: Self.dotArtworkDiameter)
        dotView.center = center
        // transform이 적용돼 있어도 bounds와 중심을 따로 갱신해 회전축이 움직이지 않게 한다.
        headingContainer.bounds = bounds
        headingContainer.center = center
        let distance = Self.dotArtworkDiameter / 2 + Self.headingGap + Self.headingSize.height / 2
        // 위쪽을 향한 원본 이미지에 맞춰 북쪽 기준 위치를 원의 바로 위에 둔다.
        headingView.center = CGPoint(x: center.x, y: center.y - distance)
    }

    /// 위쪽을 향한 원본 이미지를 기준으로 사용자 방향에서 지도 회전만 뺀다.
    func configure(headingDegrees: Double?, mapHeading: Double) {
        guard let headingDegrees, headingDegrees.isFinite, (0..<360).contains(headingDegrees),
              mapHeading.isFinite else {
            headingContainer.isHidden = true
            return
        }
        headingContainer.isHidden = false
        let angle = (headingDegrees - mapHeading) * .pi / 180
        headingContainer.transform = CGAffineTransform(rotationAngle: angle)
    }
}
