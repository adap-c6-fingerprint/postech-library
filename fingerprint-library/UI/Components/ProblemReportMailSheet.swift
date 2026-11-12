import MessageUI
import SwiftUI
import UIKit

struct ProblemReportMailSheet: UIViewControllerRepresentable {
    static let recipient = "hellomaps@fpmaps.com"

    let subject: String
    let body: String
    let onFinish: () -> Void

    static var canSendMail: Bool { MFMailComposeViewController.canSendMail() }

    static func mailtoURL(subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([Self.recipient])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult, error: (any Error)?
        ) {
            onFinish()
        }
    }
}

struct ProblemReportFallbackSheet: View {
    let messageBody: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("메일 앱을 열 수 없어요")
                .typography(.body1)
                .accessibilityAddTraits(.isHeader)
            Text("아래 주소로 문제를 보내 주세요.")
                .typography(.caption1)
                .foregroundStyle(PobookUI.ColorToken.neutralTertiary)
            Text(ProblemReportMailSheet.recipient)
                .typography(.body2)
                .textSelection(.enabled)
            HStack(spacing: 12) {
                Button("주소 복사") {
                    UIPasteboard.general.string = ProblemReportMailSheet.recipient
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("problem-report-copy")
                Button("내용 복사") {
                    UIPasteboard.general.string = "\(ProblemReportMailSheet.recipient)\n\n\(messageBody)"
                }
                .buttonStyle(.bordered)
                Spacer(minLength: 0)
                Button("닫기", action: onClose)
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.height(240)])
        .accessibilityIdentifier("problem-report-fallback")
    }
}
