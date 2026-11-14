import MapKit
import UIKit

@MainActor
final class MapUserLocationAnnotationView: MKAnnotationView {
    private let dotView = UIImageView(image: UIImage(named: "MapUserLocation")?.withRenderingMode(.alwaysOriginal))
    private let headingView = UIImageView(image: UIImage(named: "MapUserHeading")?.withRenderingMode(.alwaysOriginal))
    private let headingContainer = UIView()
    private let haloView = UIView()

    private static let dotArtworkDiameter: CGFloat = 15
    private static let headingSize = CGSize(width: 15.89314, height: 12.36133)
    private static let headingGap: CGFloat = 2
    private static let headingAnimationDuration: CFTimeInterval = 0.15
    private static let headingAnimationKey = "headingRotation"
    private var headingAngle: CGFloat?

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
        zPriority = MapAnnotationPriority.user
        selectedZPriority = MapAnnotationPriority.user
        collisionMode = .circle
        isEnabled = false
        isAccessibilityElement = true
        dotView.contentMode = .scaleAspectFit
        dotView.accessibilityIdentifier = "user-location-dot-image"
        haloView.backgroundColor = .clear
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
        headingContainer.bounds = bounds
        headingContainer.center = center
        let distance = Self.dotArtworkDiameter / 2 + Self.headingGap + Self.headingSize.height / 2
        headingView.center = CGPoint(x: center.x, y: center.y - distance)
    }

    func configure(headingDegrees: Double?, mapHeading: Double, animated: Bool = false) {
        let layer = headingContainer.layer
        guard let headingDegrees, headingDegrees.isFinite, (0..<360).contains(headingDegrees),
              mapHeading.isFinite else {
            headingContainer.isHidden = true
            layer.removeAnimation(forKey: Self.headingAnimationKey)
            headingAngle = nil
            return
        }
        let wasHidden = headingContainer.isHidden
        headingContainer.isHidden = false
        let target = CGFloat((headingDegrees - mapHeading) * .pi / 180)
        let current = (layer.presentation()?.value(forKeyPath: "transform.rotation.z") as? CGFloat)
            ?? headingAngle ?? target
        let next = current + Self.shortestRotation(from: current, to: target)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        headingContainer.transform = CGAffineTransform(rotationAngle: next)
        CATransaction.commit()
        let shouldAnimate = animated && !wasHidden && headingAngle != nil
            && !UIAccessibility.isReduceMotionEnabled && abs(next - current) > 0.000_1
        if shouldAnimate {
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = current
            animation.toValue = next
            animation.duration = Self.headingAnimationDuration
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: Self.headingAnimationKey)
        } else {
            layer.removeAnimation(forKey: Self.headingAnimationKey)
        }
        headingAngle = next
    }

    private static func shortestRotation(from current: CGFloat, to target: CGFloat) -> CGFloat {
        var delta = (target - current).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        return delta
    }
    // 359°→1°처럼 북쪽을 넘을 때 반대 방향으로 한 바퀴 돌지 않도록 −π~π 범위의 가장 짧은 회전량을 쓴다.
}
