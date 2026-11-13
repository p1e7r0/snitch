import Foundation
import SnitchCore

enum FailureDescription {
    static func text(for error: Error) -> String {
        switch error {
        case let error as ConfigurationError:
            switch error {
            case .missingToken(let host):
                return "Manca il token di accesso per \(host): salvalo nelle impostazioni."
            case .unrecognizedAddress:
                return "Indirizzo della pagina non riconosciuto."
            }
        case let error as ConfluenceError:
            switch error {
            case .network:
                return "Confluence non è raggiungibile (rete o VPN assente)."
            case .authentication:
                return "Token non valido o scaduto: aggiornalo nelle impostazioni."
            case .forbidden:
                return "Non hai il permesso di modificare la pagina."
            case .notFound:
                return "Pagina non trovata, o non hai il permesso di vederla."
            case .versionConflict:
                return "La pagina è stata modificata nel frattempo."
            case .server(let status, let message):
                return message.isEmpty ? "Errore di Confluence (\(status))." : "Errore di Confluence (\(status)): \(message)"
            case .unexpectedResponse:
                return "Risposta di Confluence non riconosciuta."
            }
        case BugPageError.tableNotFound:
            return missingTableText
        case SubmissionError.tooManyConflicts:
            return "La pagina continua a essere modificata da altri."
        default:
            return "Errore locale: \(error.localizedDescription)"
        }
    }

    static var missingTableText: String {
        "Nella pagina non trovo la tabella con le colonne \(BugPage.requiredColumnTitles.joined(separator: ", "))."
    }
}
