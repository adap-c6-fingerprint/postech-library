import SwiftUI
import UIKit

struct BookNavigationProgressBar: View {
    let timeline: BookNavigationTimeline
    let stopIndex: Int
    let progress: RouteGuidanceProgress?
    var floors: [IndoorMapFloor] = []
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var markerDiameter = 22.7
    @ScaledMetric(relativeTo: .caption) private var trackHeight = 20
    @ScaledMetric(relativeTo: .caption) private var rowHeight = 28

    private let typography = DS.Typography.caption2.weight(.semibold)

    var body: some View {
        Group {
            if timeline.hasCompleteDistances {
                GeometryReader { geometry in
                    let layout = makeLayout(width: geometry.size.width)
                    if layout.width > geometry.size.width + 0.5 {
                        // 큰 글자·좁은 화면에서도 필수 문구를 자르거나 숨기지 않는다.
                        ScrollView(.horizontal) {
                            track(layout)
                        }
                        .scrollIndicators(.hidden)
                    } else {
                        track(layout)
                    }
                }
                .frame(height: rowHeight)
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

    private func makeLayout(width: CGFloat) -> BookNavigationProgressLayout {
        let metrics = typography.metrics(for: dynamicTypeSize)
        return .init(timeline: timeline, floors: floors, availableWidth: width, markerDiameter: markerDiameter) { text in
            ceil((text as NSString).size(withAttributes: [.font: metrics.font, .kern: metrics.letterSpacing]).width) + 1
        }
    }

    private func track(_ layout: BookNavigationProgressLayout) -> some View {
        ZStack(alignment: .leading) {
            // 1. 경로 전체 배경
            Rectangle().fill(.white.opacity(0.16))
                .frame(width: layout.trackWidth, height: trackHeight)
                .offset(x: layout.trackStart)

            // 2. 마일스톤 아래까지 끊김 없이 이어지는 진행 막대와 구간 문구
            ZStack(alignment: .leading) {
                Rectangle().fill(BookNavigationPalette.accent)
                    .frame(width: layout.completedWidth(timeline: timeline, stopIndex: stopIndex, progress: progress),
                           height: trackHeight)
                    .offset(x: layout.trackStart)
                ForEach(layout.items) { item in
                    segmentLabel(item)
                        .frame(width: item.width, height: rowHeight)
                        .offset(x: item.x)
                }
            }
            .frame(width: layout.width, height: rowHeight, alignment: .leading)

            // 3. 진행 막대를 가리는 마일스톤·층 이동 마커
            ZStack(alignment: .leading) {
                ForEach(layout.items) { item in
                    markerItem(item, layout: layout)
                        .frame(width: item.width, height: rowHeight)
                        .offset(x: item.x)
                }
            }
            .frame(width: layout.width, height: rowHeight, alignment: .leading)
        }
        .frame(width: layout.width, height: rowHeight, alignment: .leading)
    }

    @ViewBuilder
    private func segmentLabel(_ item: BookNavigationProgressLayout.Item) -> some View {
        switch item.content {
        case .walk(let segment):
            let completion = timeline.completion(of: segment, stopIndex: stopIndex, progress: progress)
            if let text = item.text {
                Text(text).typography(typography).fixedSize()
                    .foregroundStyle(completion > 0.5 ? Color.black : .white.opacity(0.85))
                    .accessibilityIdentifier("navigation-progress.walk.\(segment.id)")
            }
        case .approach(let kind):
            let completion = timeline.segments.first { $0.kind == kind }.map {
                timeline.completion(of: $0, stopIndex: stopIndex, progress: progress)
            } ?? 0
            Text(item.text ?? "").typography(typography).fixedSize()
                .foregroundStyle(completion > 0.5 ? Color.black : .white.opacity(0.85))
                .accessibilityIdentifier("navigation-progress.approach.\(item.id)")
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func markerItem(_ item: BookNavigationProgressLayout.Item, layout: BookNavigationProgressLayout) -> some View {
        switch item.content {
        case .marker(let kind):
            markerView(kind, width: item.width)
        case .transition(let segment):
            HStack(spacing: layout.iconSpacing) {
                Image(segment.kind == .stairs ? "annotation_stairs" : "annotation_elevator")
                    .resizable().scaledToFit().frame(width: markerDiameter, height: markerDiameter)
                Text(item.text ?? "").typography(typography).fixedSize()
                    .frame(maxWidth: .infinity)
            }
            .padding(.trailing, layout.textPadding * 2)
            .frame(width: item.width, height: markerDiameter)
            .foregroundStyle(.black)
            .background {
                Capsule().fill(BookNavigationPalette.floorTransition)
                    .frame(height: trackHeight)
            }
            .accessibilityIdentifier("navigation-progress.transition.\(segment.id)")
        default:
            EmptyView()
        }
    }

    @ViewBuilder private func markerView(_ kind: BookNavigationTimeline.MarkerKind, width: CGFloat) -> some View {
        switch kind {
        case let .waypoint(number):
            Text(String(number)).typography(.caption2.weight(.bold)).foregroundStyle(.black)
                .frame(width: width, height: markerDiameter).background(BookNavigationPalette.accent, in: Circle())
        case let .waypoints(numbers):
            Text(numbers.map(String.init).joined(separator: "·"))
                .typography(.caption2.weight(.bold)).foregroundStyle(.black).fixedSize()
                .frame(width: width, height: markerDiameter)
                .background(BookNavigationPalette.accent, in: Capsule())
        default:
            Image(asset(for: kind)).resizable().scaledToFit()
                .frame(width: markerDiameter, height: markerDiameter)
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
