import Foundation

@main
struct FavoriteShelfMarkersProof {
    @MainActor static func main() {
        let third = UUID(), fourth = UUID()
        let geometry = IndoorMapGeometry.point(.init(latitude: 36.013, longitude: 129.323))
        let map = IndoorMap(formatVersion: "1", venue: .init(sourceID: UUID(), kind: .venue,
            floorID: nil, category: nil, name: nil, geometry: geometry), floors: [
                .init(id: third, ordinal: 2, name: "3F", geometry: geometry),
                .init(id: fourth, ordinal: 3, name: "4F", geometry: geometry)
            ], features: [], diagnostics: [])
        let a = shelf("S-3F-001-A", floor: third, side: .a, start: "PR100", end: "PR199", x: 0)
        let b = shelf("S-3F-001-B", floor: third, side: .b, start: "PR200", end: "PR299", x: 2)
        let next = shelf("S-3F-002-A", floor: third, side: .a, start: "PR300", end: "PR399", x: 10)
        let upstairs = shelf("S-4F-001-A", floor: fourth, side: .a, start: "PR100", end: "PR199", x: 0)
        let labels = [a, b, next, upstairs]
        let alpha: [String?] = ["control", "alpha"]
        let beta: [String?] = ["control", "beta"]
        let gamma: [String?] = ["control", "gamma"]
        let delta: [String?] = ["control", "delta"]
        let holdings: [[String?]: [BookHolding]] = [
            // 같은 책의 복본과 양면에 있는 소장본을 중복 집계하지 않는다.
            alpha: [holding("PR150"), holding("PR150"), holding("PR250")],
            beta: [holding("PR250")],
            gamma: [holding("PR350")],
            delta: [holding("PR150", location: "c4b")],
            ["control", "unsupported"]: [holding("PR150", location: "c2b")]
        ]
        let markers = HomeMapMarkerBuilder.favorites(holdings: holdings, on: map, labels: labels)
        precondition(markers.count == 3, "A/B 면은 합치고 다른 서가·층은 분리한다")
        let shared = markers.first { $0.bookKeys == [alpha, beta] }!
        precondition(shared.floorID == third && shared.title == "찜한 도서 2권")
        precondition(shared.coordinate.longitude == (a.geometry.coordinates[0].longitude + b.geometry.coordinates[0].longitude) / 2)
        precondition(markers.contains { $0.bookKeys == [gamma] && $0.floorID == third })
        precondition(markers.contains { $0.bookKeys == [delta] && $0.floorID == fourth })
        precondition(markers == HomeMapMarkerBuilder.favorites(holdings: holdings, on: map, labels: labels.reversed()))

        let oneBook = HomeMapMarkerBuilder.favorites(holdings: [alpha: holdings[alpha]!], on: map, labels: labels)
        precondition(oneBook.count == 1 && oneBook[0].bookKeys.count == 1)
        precondition(oneBook[0].id == shared.id, "찜 수가 바뀌어도 마커 ID는 서가를 유지한다")
        precondition(HomeMapMarkerBuilder.favorites(holdings: [:], on: map, labels: labels).isEmpty)

        let cache = HomeMapMarkerCache()
        let detailMarkers = cache.markers(on: map, labels: labels, holdings: holdings,
            showsAmenities: false, hidingFavoritesFor: [a])
        precondition(detailMarkers == markers.filter { $0.id != shared.id })
        // B 면으로 보아도 같은 서가의 마커 전체를 숨기며, 다른 서가·층은 유지한다.
        precondition(cache.markers(on: map, labels: labels, holdings: holdings,
            showsAmenities: false, hidingFavoritesFor: [b]) == detailMarkers)
        let switched = cache.markers(on: map, labels: labels, holdings: holdings,
            showsAmenities: false, hidingFavoritesFor: [next])
        precondition(switched.contains(shared))
        precondition(!switched.contains { $0.bookKeys == [gamma] })
        precondition(cache.markers(on: map, labels: labels, holdings: holdings, showsAmenities: false) == markers,
            "상세를 닫으면 저장된 마커와 찜 수를 그대로 복원한다")
        precondition(cache.markers(on: map, labels: labels, holdings: [alpha: holdings[alpha]!],
            showsAmenities: false, hidingFavoritesFor: [a]).isEmpty, "단권 마커도 상세에서 숨긴다")
        precondition(cache.markers(on: map, labels: labels, holdings: holdings,
            showsAmenities: false, hiddenFavoriteMarkerIDs: [shared.id]) == detailMarkers,
            "소장 위치 로딩 전에도 클릭한 마커 ID로 숨긴다")

        let facilitiesMap = IndoorMap(formatVersion: map.formatVersion, venue: map.venue, floors: map.floors,
            features: [
                .init(sourceID: UUID(), kind: .amenity, floorID: third, category: nil, name: "프린터", geometry: geometry),
                .init(sourceID: UUID(), kind: .unit, floorID: third, category: "stairs", name: "계단", geometry: geometry)
            ], diagnostics: [])
        let withFacilities = cache.markers(on: facilitiesMap, labels: labels, holdings: holdings,
            showsAmenities: true, hidingFavoritesFor: [a])
        precondition(withFacilities.filter { $0.kind == .favorite } == detailMarkers)
        precondition(withFacilities.contains { $0.kind == .printer })
        precondition(withFacilities.contains { $0.kind == .stairs })
        let defaultFacilities = cache.markers(on: facilitiesMap, labels: labels, holdings: holdings,
            showsAmenities: false, hidingFavoritesFor: [a])
        precondition(defaultFacilities.contains { $0.kind == .stairs })
        precondition(!defaultFacilities.contains { $0.kind == .printer }, "홈의 편의시설 표시 설정을 유지한다")

        // 범위가 겹쳐 여러 실제 서가가 후보이면 각 마커가 같은 책 키를 유지한다.
        let overlap = shelf("S-3F-003-A", floor: third, side: .a, start: "PR100", end: "PR199", x: 20)
        let candidates = HomeMapMarkerBuilder.favorites(holdings: [alpha: [holding("PR150")]],
            on: map, labels: [a, overlap])
        precondition(candidates.count == 2 && candidates.allSatisfy { $0.bookKeys == [alpha] })
        precondition(candidates.allSatisfy { $0.subtitle?.contains("위치 후보") == true })
        print("PASS: single/multiple detail hides the selected shelf marker, preserves other favorites and facilities, and restores markers on return.")
    }

    private static func holding(_ call: String, location: String = "c3b") -> BookHolding {
        .init(holdingID: nil, institutionCode: "82POSTECH_INST", libraryCode: "MAIN",
              locationCode: location, locationName: nil, callNumber: call, availability: "available")
    }

    private static func shelf(_ fixture: String, floor: UUID, side: IndoorShelfLabel.Side,
                              start: String, end: String, x: Double) -> IndoorShelfLabel {
        .init(fixtureNumber: fixture, realNumber: "337", side: side, sequence: 0,
              floorID: floor, mapElementID: .init(kind: .fixture, sourceID: UUID()),
              geometry: .point(.init(latitude: 36.013, longitude: 129.323 + x * 0.00001)),
              content: .callNumberRange(start: start, end: end))
    }
}
