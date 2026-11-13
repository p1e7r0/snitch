import Foundation
import SnitchCore

enum FailureDescription {
    static func text(for error: Error) -> String {
        switch error {
        case let error as ConfigurationError:
            switch error {
            case .missingToken(let host):
                return String(localized: "The access token for \(host) is missing: save it in the settings.")
            case .unrecognizedAddress:
                return String(localized: "Page address not recognized.")
            }
        case let error as ConfluenceError:
            switch error {
            case .network:
                return String(localized: "Confluence is unreachable (no network or VPN).")
            case .authentication:
                return String(localized: "Invalid or expired token: update it in the settings.")
            case .forbidden:
                return String(localized: "You do not have permission to edit the page.")
            case .notFound:
                return String(localized: "Page not found, or you do not have permission to view it.")
            case .versionConflict:
                return String(localized: "The page was edited in the meantime.")
            case .server(let status, let message):
                return message.isEmpty
                    ? String(localized: "Confluence error (\(status)).")
                    : String(localized: "Confluence error (\(status)): \(message)")
            case .unexpectedResponse:
                return String(localized: "Unrecognized response from Confluence.")
            }
        case BugPageError.tableNotFound:
            return missingTableText
        case SubmissionError.tooManyConflicts:
            return String(localized: "The page keeps being edited by others.")
        default:
            return String(localized: "Local error: \(error.localizedDescription)")
        }
    }

    static var missingTableText: String {
        let currentLanguage = PageLanguage.current
        let columnTitles = BugPage.requiredColumnTitles(in: currentLanguage).joined(separator: ", ")
        let alternativeColumnTitles = PageLanguage.allCases
            .filter { $0 != currentLanguage }
            .map { BugPage.requiredColumnTitles(in: $0).joined(separator: ", ") }
            .joined(separator: "; ")
        return String(localized: "The page has no table with the columns \(columnTitles), or with \(alternativeColumnTitles).")
    }
}
