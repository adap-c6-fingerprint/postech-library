import SwiftUI

struct BookNavigationProgressBar: View {
    let timeline: BookNavigationTimeline
    let stopIndex: Int
    let progress: RouteGuidanceProgress?
    var floors: [IndoorMapFloor] = []

    var body: some View {
        Group {
            if timeline.hasCompleteDistances {
                GeometryReader { geometry in
                    let width = max(0, geometry.size.width - 24)
                    ZStack(alignment: .leading) {
                        ForEach(timeline.segments) { segment in
                            let length = width * timeline.fraction(for: segment)
                            let x = timeline.totalMeters > 0 ? width * segment.startMeters / timeline.totalMeters : 0
                            Rectangle().fill(.white.opacity(0.16))
                                .frame(width: max(0, length - 2), height: 20)
                                .overlay(alignment: .leading) {
                                    Rectangle().fill(BookNavigationPalette.accent)
                                        .frame(width: max(0, length - 2) * timeline.completion(of: segment, stopIndex: stopIndex, progress: progress))
                                }
                                .overlay {
                                    if length >= 48 {
                                        ViewThatFits(in: .horizontal) {
                                            Text(timeline.description(for: segment, floors: floors)).fixedSize()
                                            Text(shortTitle(for: segment)).fixedSize()
                                            Color.clear
                                        }
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundStyle(timeline.completion(of: segment, stopIndex: stopIndex, progress: progress) > 0.5
                                            ? Color.black : Color.white.opacity(0.85))
                                        .padding(.leading, 16).padding(.trailing, 8)
                                    }
                                }
                                .offset(x: x + 12)
                        }
                        ForEach(timeline.markers) { marker in
                            markerView(marker.kind)
                                .frame(width: 22.7, height: 22.7)
                                .offset(x: width * marker.fraction)
                        }
                    }
                    .frame(height: geometry.size.height)
                }
                .frame(height: 28)
            } else {
                Label("구간별 거리 확인 필요", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("경로 진행, \(stopIndex + 1)번째 책 안내 중. "
            + timeline.segments.map { timeline.description(for: $0, floors: floors) }.joined(separator: ", "))
        .accessibilityIdentifier("book-navigation-progress")
    }

    private func shortTitle(for segment: BookNavigationTimeline.Segment) -> String {
        switch segment.kind {
        case .walk: "도보 이동"
        case .elevator: "엘리베이터"
        case .stairs: "계단"
        }
    }

    @ViewBuilder private func markerView(_ kind: BookNavigationTimeline.MarkerKind) -> some View {
        switch kind {
        case let .waypoint(number):
            Text(String(number)).font(.caption2.bold()).foregroundStyle(.black)
                .frame(width: 20, height: 20).background(BookNavigationPalette.accent, in: Circle())
        case let .waypoints(numbers):
            Text(numbers.map(String.init).joined(separator: "·"))
                .font(.caption2.bold()).foregroundStyle(.black).fixedSize()
                .padding(.horizontal, 4).frame(height: 20)
                .background(BookNavigationPalette.accent, in: Capsule())
        default:
            Image(asset(for: kind)).resizable().scaledToFit()
        }
    }

    private func asset(for kind: BookNavigationTimeline.MarkerKind) -> String {
        switch kind {
        case .walk: "annotation_walk"
        case .elevator: "annotation_elevator"
        case .stairs: "annotation_stairs"
        case .book, .waypoint, .waypoints: "annotation_book"
        }
    }
}
