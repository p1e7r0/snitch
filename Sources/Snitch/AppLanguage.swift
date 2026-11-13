import Foundation

enum AppLanguage: CaseIterable {
    case system
    case english
    case italian

    private static let defaultsKey = "AppleLanguages"

    var code: String? {
        switch self {
        case .system:
            return nil
        case .english:
            return "en"
        case .italian:
            return "it"
        }
    }

    var displayName: String {
        switch self {
        case .system:
            return String(localized: "System language")
        case .english:
            return "English"
        case .italian:
            return "Italiano"
        }
    }

    static var selected: AppLanguage {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              let domain = UserDefaults.standard.persistentDomain(forName: bundleIdentifier),
              let preferredCode = (domain[defaultsKey] as? [String])?.first else {
            return .system
        }
        return allCases.first { language in
            language.code.map { preferredCode.hasPrefix($0) } ?? false
        } ?? .system
    }

    static func select(_ language: AppLanguage) {
        if let code = language.code {
            UserDefaults.standard.set([code], forKey: defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }
}
