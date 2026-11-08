import MapKit
import SwiftUI
import UIKit

/// 아이콘 중심을 지도 좌표에 고정하고, 시설 이름만 아이콘 아래에 표시한다.
@MainActor
final class HomeMapAnnotationView: MKAnnotationView {
    static let reuseID = "home-map-icon"
    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private static let maximumNameWidth: CGFloat = 120

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        bounds = CGRect(origin: .zero, size: MapAnnotationImage.size)
        centerOffset = .zero
        clipsToBounds = false
        backgroundColor = .clear
        canShowCallout = true
        displayPriority = .required
        zPriority = MapAnnotationPriority.marker
        selectedZPriority = MapAnnotationPriority.marker
        collisionMode = .circle
        clusteringIdentifier = nil
        isAccessibilityElement = true
        iconView.contentMode = .scaleAspectFit
        iconView.isUserInteractionEnabled = false
        iconView.accessibilityIdentifier = "home-marker-icon"
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.isUserInteractionEnabled = false
        nameLabel.accessibilityIdentifier = "home-marker-name"
        nameLabel.layer.shadowColor = UIColor.black.cgColor
        nameLabel.layer.shadowOpacity = 0.35
        nameLabel.layer.shadowRadius = 1
        nameLabel.layer.shadowOffset = CGSize(width: 0, height: 0.5)
        addSubview(iconView)
        addSubview(nameLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconView.image = nil
        nameLabel.attributedText = nil
        nameLabel.isHidden = true
    }

    func configure(_ annotation: HomeMapPointAnnotation) {
        self.annotation = annotation
        let marker = annotation.marker
        iconView.image = marker.kind.assetName.flatMap(MapAnnotationImage.asset(named:))
            ?? MapAnnotationImage.symbol(named: "mappin.circle.fill", tintColor: .systemCyan)
        // 지도 위 번호와 같이, 아이콘 아래 시설명은 고정 크기로 그린다.
        let metrics = DS.Typography.caption1.metrics(for: .large, scaling: .fixed)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.minimumLineHeight = metrics.lineHeight
        paragraph.maximumLineHeight = metrics.lineHeight
        nameLabel.font = metrics.font
        nameLabel.attributedText = NSAttributedString(string: marker.title, attributes: [
            .font: metrics.font,
            .kern: metrics.letterSpacing,
            .paragraphStyle: paragraph,
            .foregroundColor: UIColor(DS.ColorToken.neutralTertiary)
        ])
        nameLabel.isHidden = marker.kind == .favorite || marker.title.isEmpty
        accessibilityLabel = annotation.title
        accessibilityValue = annotation.subtitle
        accessibilityIdentifier = "home-marker-\(marker.kind.rawValue)"
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        iconView.frame = bounds
        guard !nameLabel.isHidden else {
            nameLabel.frame = .zero
            return
        }
        let size = nameLabel.sizeThatFits(CGSize(width: Self.maximumNameWidth, height: .greatestFiniteMagnitude))
        let width = min(Self.maximumNameWidth, ceil(size.width))
        nameLabel.frame = CGRect(x: bounds.midX - width / 2, y: bounds.maxY + DS.Spacing._4,
                                 width: width, height: ceil(size.height))
    }
}
