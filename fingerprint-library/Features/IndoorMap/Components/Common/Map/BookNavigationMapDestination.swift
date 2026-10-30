import MapKit

struct BookNavigationMapDestination: Equatable {
    let book: Book
    let coordinate: IndoorMapCoordinate
    let floorID: UUID
}

final class BookNavigationDestinationAnnotation: NSObject, MKAnnotation {
    let destination: BookNavigationMapDestination
    var coordinate: CLLocationCoordinate2D { destination.coordinate.clCoordinate }
    var title: String? { BookText.plainText(destination.book.title) }

    init(_ destination: BookNavigationMapDestination) { self.destination = destination }
}
