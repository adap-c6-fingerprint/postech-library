import Foundation

nonisolated struct HomeMapMarker: Equatable, Identifiable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case favorite, stairs, elevator, toilet, shop, printer, media
        case cafe, conferenceRoom, gamingRoom, groupStudyRoom, relaxZone
        case waterDispenser, entranceDesk, circulationDesk, computer, nursingRoom
        case other

        var isAlwaysVisible: Bool {
            switch self {
            case .favorite, .stairs, .elevator: true
            default: false
            }
        }

        var assetName: String? {
            switch self {
            case .favorite: "annotation_liked"
            case .stairs: "annotation_stairs"
            case .elevator: "annotation_elevator"
            case .toilet: "annotation_toilet"
            case .shop: "annotation_convenienceStore"
            case .printer: "annotation_printer"
            case .media: "annotation_tv"
            case .cafe: "annotation_cafe"
            case .conferenceRoom: "annotation_conferenceRoom"
            case .gamingRoom: "annotation_gamingRoom"
            case .groupStudyRoom: "annotation_groupStudyRoom"
            case .relaxZone: "annotation_relaxZone"
            case .waterDispenser: "annotation_waterDispenser"
            case .entranceDesk: "annotation_entranceDesk"
            case .circulationDesk: "annotation_circulationDesk"
            case .computer: "annotation_computer"
            case .nursingRoom: "annotation_nursingRoom"
            case .other: nil
            }
        }
    }

    let id: String
    let kind: Kind
    let floorID: UUID
    var coordinate: IndoorMapCoordinate
    var title: String
    var subtitle: String? = nil
    var bookKeys: Set<[String?]> = []
}

nonisolated enum HomeMapMarkerBuilder {
    static func amenities(on map: IndoorMap) -> [HomeMapMarker] {
        let markers: [HomeMapMarker] = map.features.compactMap { feature in
            guard let floor = feature.floorID, let kind = amenityKind(feature),
                  let coordinate = anchor(for: feature.geometry) else { return nil }
            let fallback: String = switch kind {
            case .stairs: "계단"
            case .elevator: "엘리베이터"
            case .toilet: "화장실"
            case .shop: "편의점"
            case .printer: "프린터·복사기"
            case .media: "영상 자료실"
            case .cafe: "카페 니어미"
            case .conferenceRoom: "미팅룸"
            case .gamingRoom: "게임룸"
            case .groupStudyRoom: feature.category?.lowercased() == "classroom" ? "강의실" : "그룹 스터디룸"
            case .relaxZone: feature.category?.lowercased() == "lounge" ? "휴게실" : "릴렉스존"
            case .waterDispenser: "정수기"
            case .entranceDesk: "출입구 데스크"
            case .circulationDesk: "대출 데스크"
            case .computer: "PC 존"
            case .nursingRoom: "수유실"
            default: "기타 시설"
            }
            return HomeMapMarker(id: "amenity-\(feature.kind.rawValue)-\(feature.sourceID)", kind: kind,
                floorID: floor, coordinate: coordinate, title: feature.name ?? fallback)
        }.sorted { $0.id < $1.id }
        return merging(markers)
    }

    private static let overlapMeters = 6.0

    private static func isPlainer(_ lhs: String, _ rhs: String) -> Bool {
        let leftHasNote = lhs.contains("(")
        let rightHasNote = rhs.contains("(")
        if leftHasNote != rightHasNote { return rightHasNote }
        if lhs.count != rhs.count { return lhs.count < rhs.count }
        return lhs < rhs
    }

    private static func merging(_ markers: [HomeMapMarker]) -> [HomeMapMarker] {
        var clusters: [[HomeMapMarker]] = []
        for marker in markers {
            let index = clusters.firstIndex { cluster in
                guard let first = cluster.first, first.kind == marker.kind, first.floorID == marker.floorID,
                      first.bookKeys.isEmpty, marker.bookKeys.isEmpty else { return false }
                return cluster.contains {
                    RoutingGeometry.distanceMeters(from: $0.coordinate, to: marker.coordinate) <= overlapMeters
                }
            }
            if let index { clusters[index].append(marker) } else { clusters.append([marker]) }
        }
        return clusters.map { cluster in
            guard cluster.count > 1, var representative = cluster.first else { return cluster[0] }
            representative.title = cluster.map(\.title).min(by: isPlainer) ?? representative.title
            representative.coordinate = IndoorMapCoordinate(
                latitude: cluster.map(\.coordinate.latitude).reduce(0, +) / Double(cluster.count),
                longitude: cluster.map(\.coordinate.longitude).reduce(0, +) / Double(cluster.count))
            return representative
        }.sorted { $0.id < $1.id }
    }

    static func favorites(holdings: [[String?]: [BookHolding]], on map: IndoorMap,
                          labels: [IndoorShelfLabel]) -> [HomeMapMarker] {
        struct Group {
            var shelves: [String: IndoorShelfLabel] = [:]
            var keys: Set<[String?]> = []
            var isCandidate = false
        }
        var groups: [String: Group] = [:]
        for (key, copies) in holdings {
            for resolution in ShelfResolver().resolve(copies, on: map, labels: labels).preferredForRoute {
                for shelf in resolution.shelves {
                    let shelfID = shelf.physicalShelfID
                    var group = groups[shelfID] ?? Group()
                    group.shelves[shelf.id] = shelf
                    group.keys.insert(key)
                    group.isCandidate = group.isCandidate || resolution.shelves.count > 1
                    groups[shelfID] = group
                }
            }
        }
        return groups.compactMap { shelfID, group in
            let shelves = group.shelves.values.sorted { $0.id < $1.id }
            let anchors = shelves.compactMap { anchor(for: $0.geometry) }
            guard let shelf = shelves.first, !anchors.isEmpty else { return nil }
            let coordinate = IndoorMapCoordinate(
                latitude: anchors.map(\.latitude).reduce(0, +) / Double(anchors.count),
                longitude: anchors.map(\.longitude).reduce(0, +) / Double(anchors.count)
            )
            return HomeMapMarker(id: "favorite-\(shelfID)", kind: .favorite,
                floorID: shelf.floorID, coordinate: coordinate,
                title: "찜한 도서 \(group.keys.count)권",
                subtitle: "\(shelf.realNumber) 서가\(group.isCandidate ? " · 위치 후보" : "")",
                bookKeys: group.keys)
        }.sorted { $0.id < $1.id }
    }

    private static func ownedKind(forCategory category: String) -> HomeMapMarker.Kind? {
        if category == "stairs" || category == "stairway" { return .stairs }
        if category == "elevator" { return .elevator }
        if category.hasPrefix("restroom") || category == "toilets" { return .toilet }
        if category == "drinkingfountain" { return .waterDispenser }
        if category == "mothersroom" { return .nursingRoom }
        if category == "information" { return .entranceDesk }
        if category == "reception.desk" { return .circulationDesk }
        return nil
    }

    private static func amenityKind(_ feature: IndoorMapElement) -> HomeMapMarker.Kind? {
        guard feature.kind == .unit || feature.kind == .amenity || feature.kind == .fixture else { return nil }
        let category = feature.category?.lowercased() ?? ""
        let name = feature.name?.lowercased() ?? ""
        let compactName = name.filter { !$0.isWhitespace }
        if let owned = Self.ownedKind(forCategory: category) {
            return feature.kind == .amenity ? owned : nil
        }
        if compactName.contains("pc존") || compactName.contains("pczone") { return .computer }
        if name.contains("편의점") || name.contains("convenience") || name.contains("gs25") { return .shop }
        if name.contains("프린터") || name.contains("복사기") || name.contains("printer") || name.contains("copier") {
            return .printer
        }
        if compactName.contains("dvd") || compactName.contains("미디어") || compactName.contains("mediaroom") {
            return .media
        }
        if compactName.contains("fun&play") || compactName.contains("funandplay")
            || compactName.contains("게임룸") || compactName.contains("gamingroom")
            || compactName.contains("gameroom") { return .gamingRoom }
        if compactName.contains("그룹스터디룸") || compactName.contains("groupstudyroom")
            || compactName.hasPrefix("gsr") || compactName.contains("토의실")
            || compactName.contains("회의실") || compactName.contains("미팅룸")
            || compactName.contains("meetingroom") || compactName.contains("conferenceroom")
            || compactName.contains("콜라보") || compactName.contains("collaboration")
            || compactName.contains("plora") || compactName.contains("플로라")
            || compactName.contains("postech1986") || compactName.contains("isss")
            || compactName.contains("국제협력팀") || compactName.contains("internationalrelations") {
            return .groupStudyRoom
        }
        if category == "classroom" || compactName.contains("강의실")
            || compactName.contains("컨퍼런스홀") || compactName.contains("conferencehall")
            || compactName.contains("스튜디오") || compactName.contains("studio") { return .conferenceRoom }
        if compactName.contains("니어미") || compactName.contains("nearme")
            || compactName.contains("카페") || compactName.contains("cafe") { return .cafe }
        if category == "lounge" || compactName.contains("휴게실") || compactName.contains("열람석")
            || compactName.contains("relaxzone") || compactName.contains("릴렉스존") { return .relaxZone }
        if compactName.contains("welcomecenter") || compactName.contains("웰컴센터")
            || compactName.contains("입학팀") || compactName.contains("admissions") { return .entranceDesk }
        if category == "coinlocker" { return nil }
        if feature.kind == .amenity || ["foodservice", "recreation"].contains(category)
            || (category == "room" && !name.isEmpty) { return .other }
        return nil
    }

    static func anchor(for geometry: IndoorMapGeometry) -> IndoorMapCoordinate? {
        if case .point(let coordinate) = geometry { return coordinate.isValid ? coordinate : nil }
        let points = geometry.coordinates.filter(\.isValid)
        guard let first = points.first else { return nil }
        let south = points.map(\.latitude).min()!, north = points.map(\.latitude).max()!
        let west = points.map(\.longitude).min()!, east = points.map(\.longitude).max()!
        for y in [0.5, 0.25, 0.75, 0.125, 0.875] {
            for x in [0.5, 0.25, 0.75, 0.125, 0.875] {
                let point = IndoorMapCoordinate(latitude: south + (north - south) * y,
                                                longitude: west + (east - west) * x)
                if geometry.contains(point) { return point }
            }
        }
        return geometry.contains(first) ? first : nil
    }
}

@MainActor
final class HomeMapMarkerCache {
    private var map: IndoorMap?
    private var labels: [IndoorShelfLabel] = []
    private var holdings: [[String?]: [BookHolding]] = [:]
    private var amenityMarkers: [HomeMapMarker]?
    private var favoriteMarkers: [HomeMapMarker] = []

    func markers(on map: IndoorMap, labels: [IndoorShelfLabel], holdings: [[String?]: [BookHolding]],
                 showsAmenities: Bool, hidingFavoritesFor shelves: [IndoorShelfLabel] = [],
                 hiddenFavoriteMarkerIDs: Set<String> = []) -> [HomeMapMarker] {
        let mapChanged = self.map != map
        if mapChanged { amenityMarkers = nil }
        if mapChanged || self.labels != labels || self.holdings != holdings {
            favoriteMarkers = HomeMapMarkerBuilder.favorites(holdings: holdings, on: map, labels: labels)
            self.labels = labels
            self.holdings = holdings
        }
        self.map = map
        if amenityMarkers == nil { amenityMarkers = HomeMapMarkerBuilder.amenities(on: map) }
        let hiddenIDs = Set(shelves.map { "favorite-\($0.physicalShelfID)" }).union(hiddenFavoriteMarkerIDs)
        let favorites = favoriteMarkers.filter { !hiddenIDs.contains($0.id) }
        return favorites + (amenityMarkers ?? []).filter { showsAmenities || $0.kind.isAlwaysVisible }
    }
}
