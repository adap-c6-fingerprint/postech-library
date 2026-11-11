import MessageUI
import SwiftUI
import UIKit

/// 문제 신고용 메일 작성 화면. 기기의 기본 메일 작성기를 그대로 띄운다.
struct ProblemReportMailSheet: UIViewControllerRepresentable {
    static let recipient = "its.johnbaek@gmail.com"

    let subject: String
    let body: String
    let onFinish: () -> Void

    static var canSendMail: Bool { MFMailComposeViewController.canSendMail() }

    /// 메일 계정이 없어 작성기를 띄울 수 없을 때 쓰는 mailto 주소.
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
