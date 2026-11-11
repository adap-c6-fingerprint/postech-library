import Foundation

nonisolated struct HomeMapMarker: Equatable, Identifiable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case favorite, stairs, elevator, toilet, shop, printer, studio
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
            case .studio: "annotation_tv"
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
    /// 겹친 핀을 합칠 때 무게중심으로 옮긴다.
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
            case .studio: "영상 스튜디오"
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

    /// 화면에서 겹쳐 보이는 거리. 핀 하나의 폭보다 좁아 두 개를 그려도 구분되지 않는다.
    private static let overlapMeters = 6.0

    /// 괄호로 덧붙인 설명이 없고 짧은 이름을 앞에 둔다.
    private static func isPlainer(_ lhs: String, _ rhs: String) -> Bool {
        let leftHasNote = lhs.contains("(")
        let rightHasNote = rhs.contains("(")
        if leftHasNote != rightHasNote { return rightHasNote }
        if lhs.count != rhs.count { return lhs.count < rhs.count }
        return lhs < rhs
    }

    /// 같은 층·같은 종류의 핀이 겹칠 만큼 가까우면 하나로 합친다.
    ///
    /// 한 계단실에 "계단"과 "계단 (아래)"가 따로 있거나 엘리베이터 두 대가 나란히 있는 경우처럼
    /// 원본이 지점을 나눠 둔 곳에서 핀이 여러 개로 보였다.
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
            // "계단 (아래)"처럼 덧붙은 설명이 없는 이름을 대표로 둔다.
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
            for resolution in BookHoldingShelfResolver().resolve(copies, on: map, labels: labels) {
                for shelf in resolution.shelves {
                    // 같은 서가의 A/B 면과 복본은 하나의 찜 마커로 표시한다.
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

    /// IMDF amenity가 표시를 맡은 분류. unit·fixture에 같은 분류가 있어도 핀을 만들지 않는다.
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
        // 같은 장소가 unit 도형과 amenity 포인트에 모두 있어 핀이 두 번 찍혔다.
        // IMDF가 표시용으로 정리한 amenity를 쓰고, unit 쪽은 직원용이 섞여 있어 제외한다.
        if let owned = Self.ownedKind(forCategory: category) {
            return feature.kind == .amenity ? owned : nil
        }
        if compactName.contains("pc존") || compactName.contains("pczone") { return .computer }
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
