import MapKit
import SwiftUI
import UIKit

/// 아이콘 중심을 지도 좌표에 고정하고 시설 이름과 찜한 책 수를 표시한다.
@MainActor
final class HomeMapAnnotationView: MKAnnotationView {
    static let reuseID = "home-map-icon"
    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let countBadge = UILabel()
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
        countBadge.textAlignment = .center
        countBadge.font = PobookUI.Typography.caption2.weight(.semibold).metrics(for: .large, scaling: .fixed).font
        countBadge.textColor = UIColor(PobookUI.ColorToken.neutralDark)
        countBadge.backgroundColor = UIColor(PobookUI.ColorToken.primaryLight)
        countBadge.clipsToBounds = true
        countBadge.isUserInteractionEnabled = false
        countBadge.accessibilityIdentifier = "home-marker-count"
        addSubview(countBadge)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconView.image = nil
        nameLabel.attributedText = nil
        nameLabel.isHidden = true
        countBadge.text = nil
        countBadge.isHidden = true
    }

    func configure(_ annotation: HomeMapPointAnnotation) {
        self.annotation = annotation
        let marker = annotation.marker
        iconView.image = marker.kind.assetName.flatMap(MapAnnotationImage.asset(named:))
            ?? MapAnnotationImage.symbol(named: "mappin.circle.fill", tintColor: .systemCyan)
        // 지도 위 번호와 같이, 아이콘 아래 시설명은 고정 크기로 그린다.
        let metrics = PobookUI.Typography.caption1.metrics(for: .large, scaling: .fixed)
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
            .foregroundColor: UIColor(PobookUI.ColorToken.neutralTertiary)
        ])
        nameLabel.isHidden = marker.kind == .favorite || marker.title.isEmpty
        countBadge.text = String(marker.bookKeys.count)
        countBadge.isHidden = marker.kind != .favorite || marker.bookKeys.count < 2
        canShowCallout = marker.kind != .favorite
        accessibilityTraits = marker.kind == .favorite ? .button : []
        accessibilityHint = marker.kind == .favorite ? "찜한 도서 상세 보기" : nil
        accessibilityLabel = annotation.title
        accessibilityValue = annotation.subtitle
        accessibilityIdentifier = "home-marker-\(marker.kind.rawValue)"
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        iconView.frame = bounds
        if countBadge.isHidden {
            countBadge.frame = .zero
        } else {
            let height: CGFloat = 18
            let width = max(height, ceil(countBadge.intrinsicContentSize.width) + 8)
            // 배지 중심을 아이콘 우측 상단(1시 30분)에 고정한다. 자릿수가 늘어도 방향은 유지한다.
            countBadge.frame = CGRect(x: bounds.maxX - width / 2, y: bounds.minY - height / 2,
                                      width: width, height: height)
            countBadge.layer.cornerRadius = height / 2
        }
        guard !nameLabel.isHidden else {
            nameLabel.frame = .zero
            return
        }
        let size = nameLabel.sizeThatFits(CGSize(width: Self.maximumNameWidth, height: .greatestFiniteMagnitude))
        let width = min(Self.maximumNameWidth, ceil(size.width))
        nameLabel.frame = CGRect(x: bounds.midX - width / 2, y: bounds.maxY + PobookUI.Spacing._4,
                                 width: width, height: ceil(size.height))
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        super.point(inside: point, with: event) || (!countBadge.isHidden && countBadge.frame.contains(point))
    }
}
