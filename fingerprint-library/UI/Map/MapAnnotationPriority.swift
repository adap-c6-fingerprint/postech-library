import MapKit

enum MapAnnotationPriority {
    static let marker = MKAnnotationViewZPriority.defaultUnselected
    static let shelf = MKAnnotationViewZPriority(rawValue: 600)
    static let route = MKAnnotationViewZPriority(rawValue: 750)
    static let user = MKAnnotationViewZPriority.max
}
