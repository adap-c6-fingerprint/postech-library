import MapKit

/// 레이블의 기준점은 서가 도형 중심이다. 길찾기 도착 좌표로 사용하지 않는다.
final class IndoorShelfLabelAnnotation: NSObject, MKAnnotation {
    let label: IndoorShelfLabel
    let coordinate: CLLocationCoordinate2D
    lazy var labelSize: CGSize = IndoorShelfLabelView.size(for: self)
    var title: String? { "\(label.realNumber)-\(label.side.rawValue)" }
    var subtitle: String? {
        switch label.content {
        case .callNumberRange(let start, let end): "\(start) ~ \(end)"
        case .category(let category): category
        case .emptyShelf: "빈 서가"
        }
    }

    init(_ label: IndoorShelfLabel) {
        self.label = label
        let rect = MapKitGeometry.mapRect(for: label.geometry)
        coordinate = MKMapPoint(x: rect.midX, y: rect.midY).coordinate
        super.init()
    }
}

/// 번호·범위를 화면 크기로 제공한다. 표시할 레이블의 겹침은 Coordinator에서 처리한다.
final class IndoorShelfLabelView: MKAnnotationView {
    static let reuseID = "indoor-shelf-label"
    private let numberLabel = UILabel()
    private let rangeLabel = UILabel()
    private var highlightsShelf = false

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        numberLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        numberLabel.textColor = .label
        numberLabel.textAlignment = .center
        rangeLabel.font = .monospacedSystemFont(ofSize: 8, weight: .regular)
        rangeLabel.textColor = .secondaryLabel
        rangeLabel.textAlignment = .center
        rangeLabel.numberOfLines = 2
        rangeLabel.lineBreakMode = .byCharWrapping
        collisionMode = .rectangle
        displayPriority = .defaultHigh
        clusteringIdentifier = nil
        isEnabled = false
        isAccessibilityElement = true
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: IndoorShelfLabelView, _: UITraitCollection) in
            if let annotation = view.annotation as? IndoorShelfLabelAnnotation {
                view.configure(annotation, highlighted: view.highlightsShelf)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func size(for annotation: IndoorShelfLabelAnnotation) -> CGSize {
        let range = UILabel()
        range.font = .monospacedSystemFont(ofSize: 8, weight: .regular)
        range.numberOfLines = 2
        range.lineBreakMode = .byCharWrapping
        range.text = annotation.subtitle
        let width = min(156, max(64, range.sizeThatFits(CGSize(width: 156, height: 100)).width))
        return CGSize(width: width + 12, height: 22 + range.sizeThatFits(CGSize(width: width, height: 100)).height)
    }

    func configure(_ annotation: IndoorShelfLabelAnnotation, highlighted: Bool = false) {
        self.annotation = annotation
        highlightsShelf = highlighted
        displayPriority = highlighted ? .required : .defaultHigh
        numberLabel.text = annotation.title
        rangeLabel.text = annotation.subtitle
        numberLabel.textColor = UIColor.label.resolvedColor(with: traitCollection)
        rangeLabel.textColor = UIColor.secondaryLabel.resolvedColor(with: traitCollection)
        let size = annotation.labelSize
        let contentWidth = size.width - 12
        let rangeHeight = size.height - 22
        numberLabel.frame = CGRect(x: 0, y: 0, width: contentWidth, height: 14)
        rangeLabel.frame = CGRect(x: 0, y: 0, width: contentWidth, height: rangeHeight)
        // 이미지 크기를 MapKit에도 전달해 번호·범위 전체를 레이블 충돌 영역으로 인식하게 한다.
        image = UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            let card = UIBezierPath(roundedRect: rect, cornerRadius: 5)
            UIColor.systemBackground.resolvedColor(with: traitCollection).setFill()
            card.fill()
            if highlighted {
                UIColor.systemOrange.withAlphaComponent(0.2).resolvedColor(with: traitCollection).setFill()
                card.fill()
            }
            (highlighted ? UIColor.systemOrange : UIColor.separator).resolvedColor(with: traitCollection).setStroke()
            card.lineWidth = highlighted ? 2 : 0.5
            card.stroke()
            context.cgContext.saveGState()
            context.cgContext.translateBy(x: 6, y: 3)
            numberLabel.layer.render(in: context.cgContext)
            context.cgContext.restoreGState()
            context.cgContext.translateBy(x: 6, y: 18)
            rangeLabel.layer.render(in: context.cgContext)
        }
        centerOffset = .zero
        accessibilityIdentifier = "shelf-label-\(annotation.label.fixtureNumber)"
        accessibilityLabel = "서가 \(annotation.label.realNumber), \(annotation.label.side.rawValue)면"
        accessibilityValue = annotation.subtitle
        accessibilityTraits = highlighted ? [.staticText, .selected] : [.staticText]
    }
}
