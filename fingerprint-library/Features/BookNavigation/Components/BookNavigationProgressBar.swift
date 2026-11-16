import SwiftUI
import UIKit

struct BookNavigationProgressBar: View {
    let timeline: BookNavigationTimeline
    let stopIndex: Int
    let progress: RouteGuidanceProgress?
    var floors: [IndoorMapFloor] = []
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let markerDiameter = BookNavigationProgressLayout.defaultMarkerDiameter
    @ScaledMetric(relativeTo: .caption) private var trackHeight = 20
    @ScaledMetric(relativeTo: .caption) private var rowHeight = 28

    private let typography = PobookUI.Typography.guidance

    var body: some View {
        Group {
            if timeline.hasCompleteDistances {
                GeometryReader { geometry in
                    let layout = makeLayout(width: geometry.size.width)
                    if layout.width > geometry.size.width + 0.5 {
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
            Rectangle().fill(PobookUI.ColorToken.RouteBar.background)
                .frame(width: layout.trackWidth, height: trackHeight)
                .offset(x: layout.trackStart)

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
            if let text = item.text {
                Text(text).typography(typography).fixedSize()
                    .foregroundStyle(PobookUI.ColorToken.RouteBar.walkGuideText)
                    .accessibilityIdentifier("navigation-progress.walk.\(segment.id)")
            }
        case .approach:
            Text(item.text ?? "").typography(typography).fixedSize()
                .foregroundStyle(PobookUI.ColorToken.RouteBar.walkGuideText)
                .accessibilityIdentifier("navigation-progress.approach.\(item.id)")
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func markerItem(_ item: BookNavigationProgressLayout.Item, layout: BookNavigationProgressLayout) -> some View {
        switch item.content {
        case .marker(let kind):
            markerView(kind)
        case .transition(let segment):
            HStack(spacing: layout.iconSpacing) {
                Image(asset(for: segment.kind == .stairs ? .stairs : .elevator))
                    .renderingMode(.original)
                    .resizable().scaledToFit().frame(width: markerDiameter, height: markerDiameter)
                Text(item.text ?? "").typography(typography).fixedSize()
                    .foregroundStyle(PobookUI.ColorToken.RouteBar.elevatorGuideText)
                    .frame(maxWidth: .infinity)
            }
            .padding(.trailing, layout.textPadding * 2)
            .frame(width: item.width, height: markerDiameter)
            .background {
                Capsule().fill(BookNavigationPalette.floorTransition)
                    .frame(height: trackHeight)
            }
            .accessibilityIdentifier("navigation-progress.transition.\(segment.id)")
        default:
            EmptyView()
        }
    }

    @ViewBuilder private func markerView(_ kind: BookNavigationTimeline.MarkerKind) -> some View {
        switch kind {
        case let .waypoint(number):
            Text(String(number)).typography(.caption2.weight(.bold)).foregroundStyle(.black)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(width: markerDiameter, height: markerDiameter).background(BookNavigationPalette.accent, in: Circle())
        case let .waypoints(numbers):
            Text(numbers.map(String.init).joined(separator: "·"))
                .typography(.caption2.weight(.bold)).foregroundStyle(.black)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(width: markerDiameter, height: markerDiameter)
                .background(BookNavigationPalette.accent, in: Capsule())
        default:
            Image(asset(for: kind)).renderingMode(.original).resizable().scaledToFit()
                .frame(width: markerDiameter, height: markerDiameter)
        }
    }

    private func asset(for kind: BookNavigationTimeline.MarkerKind) -> String {
        switch kind {
        case .walk: "navigationAnnotations/walk"
        case .elevator: "navigationAnnotations/elevator"
        case .stairs: "navigationAnnotations/stairs"
        case .book, .waypoint, .waypoints: "navigationAnnotations/book"
        }
    }
}
