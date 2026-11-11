import SwiftUI

struct HorizontalBookPullToRefresh: ViewModifier {
    let isEnabled: Bool
    let cardStride: CGFloat
    let coverHeight: CGFloat
    let refreshID: UUID?
    let isRefreshing: Bool
    @Binding var isAtEnd: Bool
    let onNearEnd: () -> Void
    let onRefresh: () -> Void

    @State private var scroll = ScrollSample()
    private static let refreshDistance: CGFloat = 24

    private struct ScrollSample: Equatable {
        var isNearEnd = false
        var isAtEnd = false
        var pullDistance: CGFloat = 0
        var trailingGap: CGFloat = 0

        init() {}

        init(geometry: ScrollGeometry, cardStride: CGFloat) {
            let visibleRect = geometry.visibleRect
            guard visibleRect.width > 0, geometry.contentSize.width > 0 else { return }
            let remaining = geometry.contentSize.width - visibleRect.maxX
            isNearEnd = remaining <= cardStride + 12
            isAtEnd = remaining <= 12
            pullDistance = HorizontalBookPullToRefresh.pullDistance(geometry)
            trailingGap = max(0, -remaining)
        }
    }

    func body(content: Content) -> some View {
        content
            .scrollBounceBehavior(isEnabled ? .always : .basedOnSize, axes: .horizontal)
            .onScrollGeometryChange(for: ScrollSample.self) { geometry in
                isEnabled ? ScrollSample(geometry: geometry, cardStride: cardStride) : ScrollSample()
            } action: { old, new in
                scroll = new
                if isAtEnd != new.isAtEnd { isAtEnd = new.isAtEnd }
                if !old.isNearEnd, new.isNearEnd { onNearEnd() }
            }
            .onScrollPhaseChange { oldPhase, newPhase, context in
                guard isEnabled, oldPhase == .interacting,
                      newPhase == .decelerating || newPhase == .idle else { return }
                let releaseDistance = Self.pullDistance(context.geometry)
                let distance = releaseDistance > 0 ? releaseDistance : scroll.pullDistance
                if distance >= Self.refreshDistance { onRefresh() }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: refreshID) { _, newID in
                isEnabled && newID != nil
            }
            .overlay(alignment: .topTrailing) { indicator.frame(height: coverHeight) }
    }

    private static func pullDistance(_ geometry: ScrollGeometry) -> CGFloat {
        let visibleRect = geometry.visibleRect
        let restingEnd = max(
            geometry.contentSize.width + geometry.contentInsets.trailing,
            visibleRect.width - geometry.contentInsets.leading
        )
        return max(0, visibleRect.maxX - restingEnd)
    }

    @ViewBuilder
    private var indicator: some View {
        if isEnabled, scroll.trailingGap >= 22 {
            Group {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.secondary)
                        .accessibilityLabel("새 추천 도서 불러오는 중")
                } else if scroll.pullDistance > 0 {
                    let progress = min(1, scroll.pullDistance / Self.refreshDistance)
                    Image(systemName: "progress.indicator")
                        .font(.system(size: 19))
                        .foregroundStyle(.secondary)
                        .mask {
                            AngularGradient(
                                stops: [.init(color: .black, location: progress), .init(color: .clear, location: progress)],
                                center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)
                            )
                        }
                        .accessibilityHidden(true)
                }
            }
            .frame(width: scroll.trailingGap)
            .allowsHitTesting(false)
        }
    }
}
