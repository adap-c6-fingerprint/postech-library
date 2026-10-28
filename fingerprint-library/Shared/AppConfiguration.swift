import Foundation

enum AppConfiguration {
    static var nationalLibraryAPIKey: String? {
        value(for: "NATIONAL_LIBRARY_API_KEY")
    }

    static var yes24APIKey: String? {
        value(for: "YES24_API_KEY")
    }

    static var data4LibraryAPIKey: String? {
        value(for: "DATA4LIBRARY_API_KEY")
    }

    static var primoAPIKey: String? {
        value(for: "PRIMO_API_KEY")
    }

    static var primoProxyURL: String? {
        value(for: "PRIMO_PROXY_URL")
    }

    private static func value(for key: String) -> String? {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
            !value.isEmpty,
            !value.hasPrefix("$(")
        else {
            return nil
        }

        return value
    }
}
