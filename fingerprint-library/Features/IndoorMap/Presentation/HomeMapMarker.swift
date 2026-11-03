import Foundation

nonisolated struct HomeMapMarker: Equatable, Identifiable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case favorite, stairs, elevator, toilet, shop, printer, studio
        case cafe, conferenceRoom, gamingRoom, groupStudyRoom, relaxZone, other

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
            case .studio: "annotation_tv"
            case .cafe: "annotation_cafe"
            case .conferenceRoom: "annotation_conferenceRoom"
            case .gamingRoom: "annotation_gamingRoom"
            case .groupStudyRoom: "annotation_groupStudyRoom"
            case .relaxZone: "annotation_relaxZone"
            case .other: nil
            }
        }
    }

    let id: String
    let kind: Kind
    let floorID: UUID
    let coordinate: IndoorMapCoordinate
    let title: String
    var subtitle: String? = nil
    var shelfID: IndoorMapElement.ID? = nil
}

nonisolated enum HomeMapMarkerBuilder {
    static func amenities(on map: IndoorMap) -> [HomeMapMarker] {
        map.features.compactMap { feature in
            guard let floor = feature.floorID, let kind = amenityKind(feature),
                  let coordinate = anchor(for: feature.geometry) else { return nil }
            let fallback: String = switch kind {
            case .stairs: "계단"
            case .elevator: "엘리베이터"
            case .toilet: "화장실"
            case .shop: "편의점"
            case .printer: "프린터·복사기"
            case .studio: "영상 스튜디오"
            case .cafe: "카페 니어미"
            case .conferenceRoom: "미팅룸"
            case .gamingRoom: "게임룸"
            case .groupStudyRoom: feature.category?.lowercased() == "classroom" ? "강의실" : "그룹 스터디룸"
            case .relaxZone: feature.category?.lowercased() == "lounge" ? "휴게실" : "릴렉스존"
            default: "기타 시설"
            }
            return HomeMapMarker(id: "amenity-\(feature.kind.rawValue)-\(feature.sourceID)", kind: kind,
                floorID: floor, coordinate: coordinate, title: feature.name ?? fallback)
        }.sorted { $0.id < $1.id }
    }

    static func favorites(holdings: [[String?]: [BookHolding]], on map: IndoorMap,
                          labels: [IndoorShelfLabel]) -> [HomeMapMarker] {
        struct Group {
            let shelf: IndoorShelfLabel
            var keys: Set<[String?]> = []
            var isCandidate = false
        }
        var groups: [IndoorMapElement.ID: Group] = [:]
        for (key, copies) in holdings {
            for resolution in BookHoldingShelfResolver().resolve(copies, on: map, labels: labels) {
                for shelf in resolution.shelves {
                    var group = groups[shelf.mapElementID] ?? Group(shelf: shelf)
                    group.keys.insert(key)
                    group.isCandidate = group.isCandidate || resolution.shelves.count > 1
                    groups[shelf.mapElementID] = group
                }
            }
        }
        return groups.values.compactMap { group in
            guard let coordinate = anchor(for: group.shelf.geometry) else { return nil }
            return HomeMapMarker(id: "favorite-\(group.shelf.mapElementID.sourceID)", kind: .favorite,
                floorID: group.shelf.floorID, coordinate: coordinate,
                title: "찜한 도서 \(group.keys.count)권",
                subtitle: "\(group.shelf.realNumber) 서가\(group.isCandidate ? " · 위치 후보" : "")",
                shelfID: group.shelf.mapElementID)
        }.sorted { $0.id < $1.id }
    }

    private static func amenityKind(_ feature: IndoorMapElement) -> HomeMapMarker.Kind? {
        guard feature.kind == .unit || feature.kind == .amenity || feature.kind == .fixture else { return nil }
        let category = feature.category?.lowercased() ?? ""
        let name = feature.name?.lowercased() ?? ""
        let compactName = name.filter { !$0.isWhitespace }
        if category == "stairs" || category == "stairway" { return .stairs }
        if category == "elevator" { return .elevator }
        if category.hasPrefix("restroom") || category == "toilets" { return .toilet }
        if name.contains("편의점") || name.contains("convenience") || name.contains("gs25") { return .shop }
        if name.contains("프린터") || name.contains("복사기") || name.contains("printer") || name.contains("copier") {
            return .printer
        }
        if name.contains("영상스튜디오") || name.contains("영상 스튜디오") || name.contains("video studio") { return .studio }
        if category == "classroom" || compactName.contains("강의실")
            || compactName.hasPrefix("gsr") || compactName.contains("groupstudyroom")
            || compactName.contains("무은재회의실") { return .groupStudyRoom }
        if compactName.contains("미팅룸") || compactName.contains("meetingroom")
            || compactName.contains("conferenceroom") { return .conferenceRoom }
        if compactName.contains("니어미") || compactName.contains("nearme")
            || compactName.contains("카페") || compactName.contains("cafe") { return .cafe }
        if compactName.contains("게임룸") || compactName.contains("gamingroom")
            || compactName.contains("gameroom") { return .gamingRoom }
        if category == "lounge" || compactName.contains("휴게실")
            || compactName.contains("relaxzone") || compactName.contains("릴렉스존") { return .relaxZone }
        // 창고·기계실·사무실 등 비공개 공간과 일반 가구에는 시설 핀을 만들지 않는다.
        if feature.kind == .amenity || ["foodservice", "recreation"].contains(category)
            || (category == "room" && !name.isEmpty) { return .other }
        return nil
    }

    /// 도형 안의 점만 선택한다. 오목한 방이나 내부 구멍의 바깥으로 핀이 나가지 않게 한다.
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

/// 센서 위치·카메라만 바뀔 때 청구기호 범위를 다시 해석하지 않는다.
@MainActor
final class HomeMapMarkerCache {
    private var map: IndoorMap?
    private var labels: [IndoorShelfLabel] = []
    private var holdings: [[String?]: [BookHolding]] = [:]
    private var amenityMarkers: [HomeMapMarker]?
    private var favoriteMarkers: [HomeMapMarker] = []

    func markers(on map: IndoorMap, labels: [IndoorShelfLabel], holdings: [[String?]: [BookHolding]],
                 showsAmenities: Bool) -> [HomeMapMarker] {
        let mapChanged = self.map != map
        if mapChanged { amenityMarkers = nil }
        if mapChanged || self.labels != labels || self.holdings != holdings {
            favoriteMarkers = HomeMapMarkerBuilder.favorites(holdings: holdings, on: map, labels: labels)
            self.labels = labels
            self.holdings = holdings
        }
        self.map = map
        if amenityMarkers == nil { amenityMarkers = HomeMapMarkerBuilder.amenities(on: map) }
        return favoriteMarkers + (amenityMarkers ?? []).filter { showsAmenities || $0.kind.isAlwaysVisible }
    }
}
