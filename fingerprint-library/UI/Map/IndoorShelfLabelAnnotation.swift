import MapKit

final class IndoorShelfLabelAnnotation: NSObject, MKAnnotation {
    let presentation: IndoorShelfLabelPresentation
    var coordinate: CLLocationCoordinate2D { presentation.coordinate }
    var title: String? { presentation.text }
    var displayText: String {
        presentation.level == .group && !presentation.text.contains("\n")
            ? presentation.text.replacingOccurrences(of: "~", with: "\n~") : presentation.text
    }
    var subtitle: String? {
        presentation.members.map { label in
            switch label.content {
            case .callNumberRange(let start, let end): "\(start) ~ \(end)"
            case .category(let category): category
            case .emptyShelf: "빈 서가"
            }
        }.joined(separator: ", ")
    }
    lazy var labelSize = IndoorShelfLabelView.size(for: self)
    var layoutAngle: CGFloat = 0

    init(_ presentation: IndoorShelfLabelPresentation) { self.presentation = presentation }
}

final class IndoorShelfLabelView: MKAnnotationView {
    static let reuseID = "indoor-shelf-label"
    private let textLabel = UILabel()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        collisionMode = .rectangle
        clusteringIdentifier = nil
        isEnabled = false
        isAccessibilityElement = true
        textLabel.textAlignment = .center
        textLabel.numberOfLines = 0
        textLabel.backgroundColor = .clear
        textLabel.isUserInteractionEnabled = false
        textLabel.accessibilityIdentifier = "shelf-label-text"
        textLabel.layer.shadowColor = UIColor.black.cgColor
        textLabel.layer.shadowOpacity = 0.25
        textLabel.layer.shadowRadius = 1
        textLabel.layer.shadowOffset = .zero
        addSubview(textLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static let typography = PobookUI.Typography.caption1

    private static var font: UIFont {
        UIFont(name: typography.fontName, size: typography.size)
            ?? .systemFont(ofSize: typography.size, weight: .regular)
    }

    private static func text(for annotation: IndoorShelfLabelAnnotation, highlighted: Bool = false) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.minimumLineHeight = typography.lineHeight
        paragraph.maximumLineHeight = typography.lineHeight
        return NSAttributedString(string: annotation.displayText, attributes: [
            .font: font,
            .kern: typography.letterSpacing,
            .paragraphStyle: paragraph,
            .foregroundColor: UIColor.white.withAlphaComponent(highlighted ? 1 : 0.82),
            .strokeColor: UIColor.black.withAlphaComponent(0.75),
            .strokeWidth: -2.5
        ])
    }

    static func size(for annotation: IndoorShelfLabelAnnotation) -> CGSize {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = font
        label.attributedText = text(for: annotation)
        let size = label.sizeThatFits(CGSize(width: 180, height: 100))
        return CGSize(width: ceil(size.width) + 4, height: ceil(size.height) + 2)
    }

    func configure(_ annotation: IndoorShelfLabelAnnotation, highlighted: Bool = false) {
        self.annotation = annotation
        let size = annotation.labelSize
        let angle = annotation.layoutAngle
        let width = abs(cos(angle)) * size.width + abs(sin(angle)) * size.height
        let height = abs(sin(angle)) * size.width + abs(cos(angle)) * size.height
        bounds = CGRect(x: 0, y: 0, width: width, height: height)
        centerOffset = .zero
        textLabel.transform = .identity
        textLabel.bounds = CGRect(origin: .zero, size: size)
        textLabel.center = CGPoint(x: bounds.midX, y: bounds.midY)
        textLabel.font = Self.font
        textLabel.attributedText = Self.text(for: annotation, highlighted: highlighted)
        textLabel.transform = CGAffineTransform(rotationAngle: angle)
        displayPriority = .required
        zPriority = MapAnnotationPriority.shelf
        selectedZPriority = MapAnnotationPriority.shelf
        accessibilityIdentifier = "shelf-label-\(annotation.presentation.id)"
        accessibilityLabel = "서가 \(annotation.presentation.text.replacingOccurrences(of: "\n", with: ", "))"
        accessibilityValue = annotation.subtitle
        accessibilityTraits = highlighted ? [.staticText, .selected] : [.staticText]
    }
}
