import SwiftUI

struct BookRoutePreparingView: View {
    let onBack: () -> Void
    let onGoHome: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            PobookUI.ColorToken.neutralDark.ignoresSafeArea()
            HStack {
                LibraryBackButton(identifier: "route-preparing-back", action: onBack)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            content
            actions
        }
        .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("route-preparing")
    }

    private var content: some View {
        VStack(spacing: 0) {
            BookRoutePreparingIndicator()
                .padding(.top, 220)
            VStack(spacing: 8) {
                Text("길찾기 준비 중...")
                    .typography(.title1)
                    .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("route-preparing-title")
                Text("최적 경로로 빠르게 안내해 드릴게요.")
                    .typography(.body1)
                    .foregroundStyle(PobookUI.ColorToken.neutralTertiary)
                    .accessibilityIdentifier("route-preparing-message")
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 106)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var actions: some View {
        Button(action: onGoHome) {
            Text("홈으로 돌아가기")
                .typography(.button)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
                .background(Color(white: 0.16), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("route-preparing-home")
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

private struct BookRoutePreparingIndicator: View {
    private static let cycleDuration: TimeInterval = 0.5
    @Environment(\.accessibilityReduceMotion) private var isReduceMotionEnabled

    var body: some View {
        TimelineView(.animation(paused: isReduceMotionEnabled)) { context in
            symbol(progress: isReduceMotionEnabled ? 1 : progress(at: context.date))
        }
        .frame(width: 69, height: 69)
        .accessibilityElement()
        .accessibilityLabel("길찾기 준비 중")
        .accessibilityIdentifier("route-preparing-indicator")
    }

    private func progress(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.cycleDuration) / Self.cycleDuration
    }

    private func symbol(progress: Double) -> some View {
        Image(systemName: "progress.indicator")
            .font(.system(size: 56, weight: .medium))
            .foregroundStyle(
                LinearGradient(
                    colors: [PobookUI.ColorToken.primaryLight, PobookUI.ColorToken.primaryDark],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .mask {
                AngularGradient(
                    stops: [.init(color: .black, location: progress), .init(color: .clear, location: progress)],
                    center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)
                )
            }
    }
}

#if DEBUG
#Preview("길찾기 준비 중") {
    BookRoutePreparingView(onBack: {}, onGoHome: {})
}
#endif
