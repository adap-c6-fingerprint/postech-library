import SwiftUI

/// 길안내를 준비하지 못했을 때 보여 주는 화면.
///
/// 원인에 따라 문구와 마지막 보조 동작이 달라진다. 데이터 문제는 문제 신고로,
/// 위치가 도서관 밖인 경우는 책카트에 담아 두는 쪽으로 안내한다.
struct BookRouteFailureView: View {
    enum Kind: Equatable {
        /// 길찾기 자료를 불러오지 못했다.
        case dataUnavailable
        /// 목적지까지의 안내를 만들 수 없다.
        case destinationUnavailable
        /// 현재 위치가 도서관 길찾기 범위 밖이다.
        case outsideLibrary
    }

    let kind: Kind
    /// 원인 확인용 에러 코드와 위치 상태. 화면 아래에 작게 표시한다.
    var diagnostic: String?
    var isRetrying = false
    let onBack: () -> Void
    let onRetry: () -> Void
    let onGoHome: () -> Void
    /// 도서관 밖에서만 쓰는 보조 동작. 담을 책이 없으면 전달하지 않는다.
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
        .foregroundStyle(DS.ColorToken.neutralPrimary)
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
                .foregroundStyle(DS.ColorToken.neutralDark, DS.ColorToken.primaryLight)
                .accessibilityHidden(true)
            VStack(spacing: 16) {
                Text(title)
                    .typography(.title1)
                    .foregroundStyle(DS.ColorToken.neutralPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("route-failure-title")
                Text(message)
                    .typography(.body2)
                    .foregroundStyle(DS.ColorToken.neutralTertiary)
                    .accessibilityIdentifier("route-failure-message")
                if let diagnostic {
                    Text(diagnostic)
                        .font(.caption2.monospaced())
                        .foregroundStyle(DS.ColorToken.neutralTertiary.opacity(0.7))
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
                    if isRetrying { ProgressView().tint(DS.ColorToken.neutralDark) }
                    Text("다시 시도하기").typography(.button)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(DS.ColorToken.neutralDark)
                .background(DS.ColorToken.primaryLight, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isRetrying)
            .accessibilityIdentifier("route-failure-retry")

            Button(action: onGoHome) {
                Text("홈으로 돌아가기")
                    .typography(.button)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(DS.ColorToken.neutralPrimary)
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
                    .foregroundStyle(DS.ColorToken.neutralPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("route-failure-add-to-cart")
        } else {
            Button(action: onReportProblem) {
                Text("문제 신고하기")
                    .typography(.body2)
                    .underline()
                    .foregroundStyle(DS.ColorToken.neutralPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("route-failure-report")
        }
    }
}

extension BookRouteFailureView.Kind {
    /// 오류 문구에서 원인을 되찾는다. 문구는 ``IndoorRoutingError``가 만든 것과 같은 값이다.
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
