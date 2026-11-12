import Foundation

/// 검색 결과의 강조 태그와 책 소개의 HTML을 실행하지 않고 일반 텍스트로 표시한다.
nonisolated enum BookText {
    static func plainText(_ value: String) -> String {
        var text = value
            .replacingOccurrences(
                of: #"<(script|style)\b[^>]*>[\s\S]*?</\1\s*>"#,
                with: "", options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"<br\b[^>]*>|</(?:p|div|li|h[1-6])\s*>"#,
                with: "\n", options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)

        let entities = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "]
        let pattern = #"&(amp|lt|gt|quot|apos|nbsp|#[0-9]+|#x[0-9a-fA-F]+);"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let range = Range(match.range, in: text),
                      let nameRange = Range(match.range(at: 1), in: text) else { continue }
                let name = String(text[nameRange])
                let replacement: String?
                if name.hasPrefix("#") {
                    let isHex = name.hasPrefix("#x")
                    let digits = name.dropFirst(isHex ? 2 : 1)
                    replacement = UInt32(digits, radix: isHex ? 16 : 10)
                        .flatMap(UnicodeScalar.init).map(String.init)
                } else {
                    replacement = entities[name]
                }
                if let replacement { text.replaceSubrange(range, with: replacement) }
            }
        }
        return text.replacingOccurrences(of: #"\n[\t ]*\n(?:[\t ]*\n)+"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
