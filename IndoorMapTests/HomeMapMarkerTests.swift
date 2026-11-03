import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct HomeMapMarkerTests {
    @Test("실제 도면의 시설 아이콘을 연결하고 휴게실·강의실에도 같은 아이콘과 올바른 이름을 표시한다")
    func actualAmenities() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let markers = HomeMapMarkerBuilder.amenities(on: map)
        #expect(markers.filter { $0.kind == .stairs }.count == 22)
        #expect(markers.filter { $0.kind == .elevator }.count == 12)
        #expect(markers.filter { $0.kind == .toilet }.count == 20)
        for kind in [HomeMapMarker.Kind.shop, .printer, .studio, .cafe, .gamingRoom] {
            #expect(markers.filter { $0.kind == kind }.count == 1)
        }
        #expect(markers.filter { $0.kind == .conferenceRoom }.count == 2)
        #expect(markers.filter { $0.kind == .relaxZone }.count == 2)
        let groupRooms = markers.filter { $0.kind == .groupStudyRoom }
        #expect(groupRooms.count == 17)
        #expect(groupRooms.filter { $0.title.hasPrefix("GSR-") }.count == 12)
        let assignedNames: [(String, String)] = [
            ("커피 니어미", "annotation_cafe"),
            ("미팅룸 중-1", "annotation_conferenceRoom"),
            ("미팅룸 중-2", "annotation_conferenceRoom"),
            ("GSR-01", "annotation_groupStudyRoom"),
            ("무은재 회의실", "annotation_groupStudyRoom"),
            ("GS25 편의점", "annotation_convenienceStore"),
            ("게임룸", "annotation_gamingRoom"),
            ("프린터/복사기", "annotation_printer"),
            ("Relax Zone", "annotation_relaxZone"),
            ("영상스튜디오", "annotation_tv")
        ]
        for (title, assetName) in assignedNames {
            let marker = try #require(markers.first { $0.title == title })
            #expect(marker.kind.assetName == assetName)
        }
        let classrooms = map.features.filter { $0.category == "classroom" }
        #expect(classrooms.count == 4)
        for classroom in classrooms {
            let marker = try #require(markers.first { $0.id == "amenity-unit-\(classroom.sourceID)" })
            #expect(marker.kind.assetName == "annotation_groupStudyRoom")
            #expect(marker.title == "강의실")
        }
        let unnamedLounge = try #require(map.features.first { $0.category == "lounge" && $0.name == nil })
        let loungeMarker = try #require(markers.first { $0.id == "amenity-unit-\(unnamedLounge.sourceID)" })
        #expect(loungeMarker.kind.assetName == "annotation_relaxZone")
        #expect(loungeMarker.title == "휴게실")
        #expect(!markers.contains { $0.kind == .other })
        #expect(!markers.contains { $0.title.contains("EPS") || $0.title.contains("사무실") || $0.title.contains("공조실") })
        #expect(Set(markers.map(\.id)).count == markers.count)
        for marker in markers {
            let floor = try #require(map.floors.first { $0.id == marker.floorID })
            #expect(floor.geometry.contains(marker.coordinate))
        }
    }

    @Test("찜한 여러 책과 복본이 같은 서가에 있으면 하트 하나와 고유 도서 수로 묶는다")
    func groupsFavoriteShelves() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        let first: [String?] = ["control", "alma991000000001"]
        let second: [String?] = ["control", "alma991000000002"]
        let holding = BookHoldingTestData.holding()
        let markers = HomeMapMarkerBuilder.favorites(holdings: [first: [holding, holding], second: [holding]],
                                                    on: map, labels: labels)
        #expect(markers.count == 1)
        let marker = try #require(markers.first)
        #expect(marker.kind == .favorite)
        #expect(marker.kind.assetName == "annotation_liked")
        #expect(marker.title == "찜한 도서 2권")
        let shelf = try #require(labels.first { $0.fixtureNumber == "S-3F-616-B" })
        #expect(marker.floorID == shelf.floorID)
        #expect(shelf.geometry.contains(marker.coordinate))
        #expect(!marker.subtitle!.contains("후보"))
        #expect(HomeMapMarkerBuilder.favorites(holdings: [second: [holding]], on: map, labels: labels).first?.title == "찜한 도서 1권")
        #expect(HomeMapMarkerBuilder.favorites(holdings: [:], on: map, labels: labels).isEmpty)
    }

    @Test("3·4층을 구분하고 범위가 겹치면 후보임을 알리며 매핑할 수 없는 소장은 핀을 만들지 않는다")
    func preservesLocationEvidence() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        let key: [String?] = ["control", "alma991000000001"]
        let mixed = HomeMapMarkerBuilder.favorites(holdings: [key: [BookHoldingTestData.holding(), BookHoldingTestData.holding(code: "c4b")]], on: map, labels: labels)
        #expect(Set(mixed.map(\.floorID)).count == 2)
        let ambiguous = HomeMapMarkerBuilder.favorites(holdings: [key: [BookHoldingTestData.holding(call: "AM79 .K8 2024")]], on: map, labels: labels)
        #expect(ambiguous.count == 2)
        #expect(ambiguous.allSatisfy { $0.subtitle?.contains("위치 후보") == true })
        let unsupported = [BookHoldingTestData.holding(code: "smart"), BookHoldingTestData.holding(call: ""), BookHoldingTestData.holding(call: "ZZ9999.A1")]
        #expect(HomeMapMarkerBuilder.favorites(holdings: [key: unsupported], on: map, labels: labels).isEmpty)
    }

    @Test("도형 중앙에 내부 구멍이 있으면 구멍 바깥의 좌표에 표시한다")
    func anchorAvoidsHole() throws {
        let geometry = IndoorMapGeometry.polygon([IndoorMapTestData.square, IndoorMapTestData.hole])
        let anchor = try #require(HomeMapMarkerBuilder.anchor(for: geometry))
        #expect(geometry.contains(anchor))
        #expect(HomeMapMarkerBuilder.anchor(for: .polygon([])) == nil)
    }

    @Test("표시 결과를 재사용해도 찜 취소·시설 전환·서가 자료 변경은 즉시 반영한다")
    func invalidatesCachedMarkers() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        let key: [String?] = ["control", "alma991000000001"]
        let holdings = [key: [BookHoldingTestData.holding()]]
        let cache = HomeMapMarkerCache()
        let favorites = cache.markers(on: map, labels: labels, holdings: holdings, showsAmenities: false)
        #expect(favorites.count == 1)
        let all = cache.markers(on: map, labels: labels, holdings: holdings, showsAmenities: true)
        #expect(all.filter { $0.kind == .favorite } == favorites)
        #expect(all.contains { $0.kind == .stairs })
        #expect(cache.markers(on: map, labels: labels, holdings: holdings, showsAmenities: false) == favorites)
        #expect(cache.markers(on: map, labels: [], holdings: holdings, showsAmenities: false).isEmpty)
        #expect(cache.markers(on: map, labels: labels, holdings: holdings, showsAmenities: false) == favorites)
        #expect(cache.markers(on: map, labels: labels, holdings: [:], showsAmenities: false).isEmpty)
    }
}
