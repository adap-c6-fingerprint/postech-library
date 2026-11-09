import Foundation

/// 필수 문구의 폭을 먼저 확보한 뒤 남은 폭을 실제 거리 비율로 나눈다.
/// 화면 배치만 조정하며 원본 경로의 거리·도착 지점·진행률은 변경하지 않는다.
struct BookNavigationProgressLayout {
    enum Content: Equatable {
        case marker(BookNavigationTimeline.MarkerKind)
        case walk(BookNavigationTimeline.Segment)
        case transition(BookNavigationTimeline.Segment)
        case approach(BookNavigationTimeline.Kind)
    }

    struct Item: Identifiable, Equatable {
        let id: Int
        let content: Content
        let x: CGFloat
        let width: CGFloat
        let text: String?
    }

    struct SegmentSpan: Identifiable, Equatable {
        var id: Int { segment.id }
        let segment: BookNavigationTimeline.Segment
        let x: CGFloat
        let width: CGFloat
    }

    let items: [Item]
    let width: CGFloat
    let markerDiameter: CGFloat
    let textPadding: CGFloat
    let iconSpacing: CGFloat

    var trackStart: CGFloat { items.first.map { $0.x + $0.width / 2 } ?? 0 }
    var trackEnd: CGFloat { items.last.map { $0.x + $0.width / 2 } ?? 0 }
    var trackWidth: CGFloat { max(0, trackEnd - trackStart) }

    /// 텍스트 배치용 칸과 별개로 진행 막대는 마일스톤 중심 아래까지 연결한다.
    var segmentSpans: [SegmentSpan] {
        let segments = items.compactMap { item -> (Item, BookNavigationTimeline.Segment)? in
            switch item.content {
            case .walk(let segment), .transition(let segment): (item, segment)
            default: nil
            }
        }
        var start = trackStart
        return segments.enumerated().map { index, entry in
            let (item, segment) = entry
            let end: CGFloat
            if index + 1 < segments.count {
                let next = segments[index + 1].0
                let between = items.filter { $0.id > item.id && $0.id < next.id }
                if let milestone = between.first(where: { if case .marker = $0.content { true } else { false } }) {
                    end = milestone.x + milestone.width / 2
                } else if between.contains(where: { if case .approach = $0.content { true } else { false } }) {
                    end = item.x + item.width
                } else if case .transition = next.content {
                    end = next.x + markerDiameter / 2
                } else {
                    end = item.x + item.width
                }
            } else {
                end = trackEnd
            }
            let boundedEnd = max(start, min(trackEnd, end))
            defer { start = boundedEnd }
            return .init(segment: segment, x: start, width: boundedEnd - start)
        }
    }

    func completedWidth(timeline: BookNavigationTimeline, stopIndex: Int, progress: RouteGuidanceProgress?) -> CGFloat {
        var end = trackStart
        for span in segmentSpans {
            let completion = timeline.completion(of: span.segment, stopIndex: stopIndex, progress: progress)
            end = span.x + span.width * completion
            if completion < 1 { break }
        }
        return min(trackWidth, max(0, end - trackStart))
    }

    init(timeline: BookNavigationTimeline, floors: [IndoorMapFloor], availableWidth: CGFloat,
         markerDiameter: CGFloat = 22.7, measureText: (String) -> CGFloat) {
        let scale = markerDiameter / 22.7
        let padding: CGFloat = 4 * scale
        self.markerDiameter = markerDiameter
        textPadding = padding
        iconSpacing = padding

        struct Entry {
            let content: Content
            let minimumWidth: CGFloat
            var meters: Double = 0
            var label: BookNavigationTimeline.Label?
            var fixedText: String?
        }
        func walkingEntry(_ segment: BookNavigationTimeline.Segment) -> Entry {
            let label = timeline.walkingLabel(for: segment, floors: floors)
            return .init(content: .walk(segment), minimumWidth: label.isRequired
                ? measureText(label.compactText) + padding * 2 : padding,
                meters: segment.meters, label: label)
        }
        func markerWidth(_ kind: BookNavigationTimeline.MarkerKind) -> CGFloat {
            guard case let .waypoints(numbers) = kind else { return markerDiameter }
            return max(markerDiameter, measureText(numbers.map(String.init).joined(separator: "·")) + padding * 2)
        }
        func lastStop(_ kind: BookNavigationTimeline.MarkerKind) -> Int? {
            switch kind {
            case .book: 0
            case .waypoint(let number): number - 1
            case .waypoints(let numbers): numbers.last.map { $0 - 1 }
            default: nil
            }
        }
        guard timeline.hasCompleteDistances else {
            items = []
            width = max(0, availableWidth)
            return
        }
        let bookMarkers = timeline.markers.filter { lastStop($0.kind) != nil }
        let stops = Set(timeline.segments.map(\.stopIndex) + bookMarkers.compactMap { lastStop($0.kind) }).sorted()
        var entries: [Entry] = [.init(content: .marker(.walk), minimumWidth: markerDiameter)]
        var encountered = Set<BookNavigationTimeline.Kind>()
        for stop in stops {
            let segments = timeline.segments.filter { $0.stopIndex == stop }
            for (index, segment) in segments.enumerated() {
                if segment.kind == .walk {
                    entries.append(walkingEntry(segment))
                } else {
                    if encountered.insert(segment.kind).inserted,
                       index == 0 || segments[index - 1].kind != .walk {
                        // 출발점이 층 이동 구간이어도 첫 이동 문구는 생략하지 않는다.
                        let label = timeline.approachLabel(for: segment, floors: floors)
                        entries.append(.init(content: .approach(segment.kind),
                            minimumWidth: measureText(label.compactText) + padding * 2, label: label))
                    }
                    let title = timeline.transitionTitle(for: segment, floors: floors)
                    entries.append(.init(content: .transition(segment),
                        minimumWidth: markerDiameter + padding + measureText(title) + padding * 2,
                        meters: segment.meters, fixedText: title))
                }
            }
            for marker in bookMarkers where lastStop(marker.kind) == stop {
                entries.append(.init(content: .marker(marker.kind), minimumWidth: markerWidth(marker.kind)))
            }
        }
        let minimumWidth = entries.reduce(0) { $0 + $1.minimumWidth }
        let contentWidth = max(availableWidth.isFinite ? availableWidth : 0, minimumWidth)
        width = contentWidth
        var extra = contentWidth - minimumWidth
        var preferredWidths = entries.map(\.minimumWidth)
        // 선택 문구를 늘리기 전에 첫 시설 이동 문구의 전체 표현을 우선 확보한다.
        for (index, entry) in entries.enumerated() {
            guard let label = entry.label, label.isRequired else { continue }
            let addition = max(0, measureText(label.fullText) + padding * 2 - entry.minimumWidth)
            if addition <= extra {
                preferredWidths[index] += addition
                extra -= addition
            }
        }
        let totalMeters = entries.reduce(0) { $0 + $1.meters }
        var x: CGFloat = 0
        items = entries.enumerated().map { index, entry in
            let itemWidth = preferredWidths[index] + (totalMeters > 0 ? extra * CGFloat(entry.meters / totalMeters) : 0)
            let text: String?
            if let label = entry.label {
                text = [label.fullText, label.compactText].first {
                    measureText($0) + padding * 2 <= itemWidth + 0.01
                }
            } else {
                text = entry.fixedText
            }
            // 모든 구간의 거리가 0이어도 끝점 마커는 마지막에 놓는다.
            let origin = totalMeters == 0 && index == entries.count - 1 ? contentWidth - itemWidth : x
            defer { x += itemWidth }
            return .init(id: index, content: entry.content, x: origin, width: itemWidth, text: text)
        }
    }
}
