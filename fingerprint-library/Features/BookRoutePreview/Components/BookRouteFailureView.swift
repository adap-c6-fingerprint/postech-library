import SwiftUI

struct BookRouteFailureView: View {
    enum Kind: Equatable {
        case dataUnavailable
        case destinationUnavailable
        case outsideLibrary
    }

    let kind: Kind
    var diagnostic: String?
    var isRetrying = false
    let onBack: () -> Void
    let onRetry: () -> Void
    let onGoHome: () -> Void
    var onAddToCart: (() -> Void)?
    let onReportProblem: () -> Void

    private var title: String {
        switch kind {
        case .dataUnavailable, .destinationUnavailable: "길안내를 준비하지 못했어요."
        case .outsideLibrary: "도서관 안에서\n길찾기를 시작해 주세요."
        }
    }

    private var message: String {
        switch kind {
        case .dataUnavailable:
            "포북이 길찾기 정보를 불러오지 못하고 있어요.\n잠시 후 다시 시도해 주세요."
        case .destinationUnavailable:
            "선택한 장소까지의 안내가 불명확해 안내를 준비하지 못했어요. 다른 장소를 검색하거나 지도에서 확인해주세요."
        case .outsideLibrary:
            "현재 위치가 도서관 길찾기 범위 밖에 있어요.\n도서관 안으로 이동한 뒤 다시 시도해 주세요."
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            HStack {
                LibraryBackButton(identifier: "route-failure-back", action: onBack)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            content
            actions
        }
        .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .accessibilityIdentifier("route-failure")
    }

    private var content: some View {
        VStack(spacing: 32) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 69))
                .frame(width: 69, height: 69)
                .symbolRenderingMode(.palette)
                .foregroundStyle(PobookUI.ColorToken.neutralDark, PobookUI.ColorToken.primaryLight)
                .accessibilityHidden(true)
            VStack(spacing: 16) {
                Text(title)
                    .typography(.title1)
                    .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("route-failure-title")
                Text(message)
                    .typography(.body2)
                    .foregroundStyle(PobookUI.ColorToken.neutralTertiary)
                    .accessibilityIdentifier("route-failure-message")
                if let diagnostic {
                    Text(diagnostic)
                        .font(.caption2.monospaced())
                        .foregroundStyle(PobookUI.ColorToken.neutralTertiary.opacity(0.7))
                        .textSelection(.enabled)
                        .accessibilityIdentifier("route-failure-code")
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            Button(action: onRetry) {
                HStack(spacing: 8) {
                    if isRetrying { ProgressView().tint(PobookUI.ColorToken.neutralDark) }
                    Text("다시 시도하기").typography(.button)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(PobookUI.ColorToken.neutralDark)
                .background(PobookUI.ColorToken.primaryLight, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isRetrying)
            .accessibilityIdentifier("route-failure-retry")

            Button(action: onGoHome) {
                Text("홈으로 돌아가기")
                    .typography(.button)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
                    .background(Color(white: 0.16), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("route-failure-home")

            tertiaryAction
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    @ViewBuilder
    private var tertiaryAction: some View {
        if kind == .outsideLibrary, let onAddToCart {
            Button(action: onAddToCart) {
                Text("책카트에 담고 닫기")
                    .typography(.body2)
                    .underline()
                    .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("route-failure-add-to-cart")
        } else {
            Button(action: onReportProblem) {
                Text("문제 신고하기")
                    .typography(.body2)
                    .underline()
                    .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("route-failure-report")
        }
    }
}

extension BookRouteFailureView.Kind {
    init(message: String?) {
        switch IndoorRoutingError.allCases.first(where: { $0.errorDescription == message }) {
        case .farFromGraph, .invalidPosition, .unknownFloor:
            self = .outsideLibrary
        case .invalidDestination, .noRoute:
            self = .destinationUnavailable
        default:
            self = .dataUnavailable
        }
    }
}
