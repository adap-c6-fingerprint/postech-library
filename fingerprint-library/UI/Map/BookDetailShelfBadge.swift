import MapKit
import UIKit

final class BookDetailShelfBadge: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let text: String

    init(_ shelf: IndoorShelfLabelPresentation) {
        coordinate = shelf.coordinate
        text = shelf.members.allSatisfy(\.isNamedShelf) ? shelf.text : "\(shelf.text)번 서가"
    }
}

final class BookDetailShelfBadgeView: MKAnnotationView {
    static let reuseID = "book-detail-shelf-badge"
    private let label = UILabel()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        backgroundColor = BookNavigationPalette.uiAccent
        displayPriority = .required
        zPriority = MapAnnotationPriority.route
        collisionMode = .rectangle
        isEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        accessibilityIdentifier = Self.reuseID

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .black
        label.textAlignment = .center
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ badge: BookDetailShelfBadge) {
        annotation = badge
        label.text = badge.text
        let size = label.intrinsicContentSize
        bounds = CGRect(x: 0, y: 0, width: ceil(size.width) + 18, height: ceil(size.height) + 14)
        label.frame = bounds
        layer.cornerRadius = bounds.height / 2
        centerOffset = CGPoint(x: 0, y: -bounds.height / 2 - 6)
        accessibilityLabel = badge.text
    }
}
