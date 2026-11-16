import Foundation
import Testing
@testable import fingerprint_library

struct LocationDiagnosticsAnalyzerTests {
    /// 위도 1e-5도 ≈ 1.11m
    static let base = IndoorMapCoordinate(latitude: 36, longitude: 129)

    func time(_ seconds: Double) -> Date { Date(timeIntervalSinceReferenceDate: 1_000 + seconds) }

    func location(_ seconds: Double, north meters: Double, accuracy: Double = 3, floor: Int? = 1)
        -> LocationDiagnosticsRecord {
        .location(.init(receivedAt: time(seconds), timestamp: time(seconds),
                        latitude: Self.base.latitude + meters / 111_195, longitude: Self.base.longitude,
                        horizontalAccuracy: accuracy, floorLevel: floor))
    }

    func guidance(_ seconds: Double, maneuver: String? = "straight", along: Double? = nil, remaining: Double? = nil,
                  quality: String = "on_route", camera: Int = 0, stop: Int = 0) -> LocationDiagnosticsRecord {
        .guidance(.init(at: time(seconds), stopIndex: stop, quality: quality, distanceAlongRoute: along,
                        remainingMeters: remaining, maneuver: maneuver, cameraRequestID: camera))
    }

    @Test func 보행_속도를_넘는_이동만_튐으로_센다() {
        let summary = LocationDiagnosticsAnalyzer.summarize([
            location(0, north: 0),
            location(1, north: 1.2),   // 보행
            location(2, north: 6),     // 4.8m/s 튐
            location(3, north: 7)
        ])
        #expect(summary.jumpCount == 1)
        #expect(abs(summary.largestJumpMeters - 4.8) < 0.1)
        #expect(summary.locationCount == 4)
    }

    @Test func 정확도는_중앙값과_p90으로_요약한다() {
        let records = (0..<10).map { location(Double($0), north: 0, accuracy: Double($0 + 1)) }
        let summary = LocationDiagnosticsAnalyzer.summarize(records)
        #expect(summary.horizontalAccuracy?.median == 5)
        #expect(summary.horizontalAccuracy?.p90 == 9)
        #expect(summary.horizontalAccuracy?.max == 10)
    }

    @Test func 짧은_시간에_안내가_되돌아가면_뒤집힘으로_센다() {
        let summary = LocationDiagnosticsAnalyzer.summarize([
            guidance(0, maneuver: "left"),
            guidance(2, maneuver: "straight"),
            guidance(4, maneuver: "left"),
            guidance(30, maneuver: "straight"),
            guidance(60, maneuver: "left")
        ])
        #expect(summary.maneuverFlipCount == 1)
    }

    @Test func 진행_거리_역행과_남은_거리_증가를_센다() {
        let summary = LocationDiagnosticsAnalyzer.summarize([
            guidance(0, along: 10, remaining: 20),
            guidance(1, along: 12, remaining: 18),
            guidance(2, along: 9, remaining: 21),
            guidance(3, along: 9.2, remaining: 20.8),
            guidance(4, along: 0, remaining: 30, stop: 1)
        ])
        #expect(summary.progressRegressionCount == 1)
        #expect(abs(summary.progressRegressionMeters - 3) < 0.001)
        #expect(summary.remainingIncreaseCount == 1)
    }

    @Test func 안내_상태는_시간_비율과_중단_횟수로_요약한다() {
        let summary = LocationDiagnosticsAnalyzer.summarize([
            guidance(0, quality: "on_route", camera: 1),
            guidance(3, quality: "inaccurate", camera: 1),
            guidance(4, quality: "on_route", camera: 3),
            guidance(7, quality: "on_route", camera: 3)
        ])
        #expect(summary.guidanceSuspensionCount == 1)
        #expect(summary.cameraRecenterCount == 2)
        #expect(abs((summary.guidanceQualityRatio["inaccurate"] ?? 0) - 1.0 / 8) < 0.001)
    }

    @Test func 기준점_마커로_정지_오차와_보행_오차를_계산한다() {
        func marker(_ seconds: Double, north meters: Double) -> LocationDiagnosticsRecord {
            .marker(.init(at: time(seconds), kind: .checkpoint,
                          latitude: Self.base.latitude + meters / 111_195, longitude: Self.base.longitude,
                          floorOrdinal: 1))
        }
        let summary = LocationDiagnosticsAnalyzer.summarize([
            marker(0, north: 0),
            location(0.5, north: 2),       // 기준점 0m 대비 2m 오차
            location(5, north: 5 + 1),     // 보간 정답 5m, 1m 오차
            marker(10, north: 10),
            location(10.5, north: 10)      // 오차 0m
        ])
        #expect(summary.checkpointErrorMeters?.count == 2)
        #expect(abs((summary.checkpointErrorMeters?.max ?? 0) - 2) < 0.05)
        #expect(summary.walkingErrorMeters?.count == 2)
    }

    @Test func 정지_중_튐과_흩어짐을_구분한다() {
        let still = LocationDiagnosticsRecord.activity(.init(
            at: time(0), startDate: time(0), isStationary: true, isWalking: false, isRunning: false,
            isAutomotive: false, isCycling: false, isUnknown: false, confidence: 2))
        let summary = LocationDiagnosticsAnalyzer.summarize([
            still,
            location(1, north: 0), location(4, north: 1), location(10, north: 0),
            location(11, north: 5), location(12, north: 0)
        ])
        #expect(summary.stationaryJumpCount == 2)
        #expect((summary.stationarySpreadMeters?.count ?? 0) == 1)
    }

    @Test func 기록은_type으로_구분된_JSON_한_줄로_왕복한다() throws {
        let records: [LocationDiagnosticsRecord] = [
            location(0, north: 1),
            guidance(1),
            .marker(.init(at: time(2), kind: .jump)),
            .event(.init(at: time(3), name: "session_started", detail: ["posture": "hand"])),
            .route(.init(at: time(4), stopIndex: 0, reason: "initial",
                         segments: [.init(floorOrdinal: 1, coordinates: [[36, 129], [36.0001, 129]])],
                         destinationLatitude: 36.0001, destinationLongitude: 129, destinationFloorOrdinal: 1))
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for record in records {
            let data = try encoder.encode(record)
            let line = try #require(String(data: data, encoding: .utf8))
            #expect(!line.contains("\n"))
            #expect(line.contains("\"type\""))
            #expect(try decoder.decode(LocationDiagnosticsRecord.self, from: data) == record)
        }
    }
}
