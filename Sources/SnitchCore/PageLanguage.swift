import Foundation

public enum PageLanguage: Sendable, CaseIterable {
    case english
    case italian

    var vocabulary: PageVocabulary {
        switch self {
        case .english:
            return .english
        case .italian:
            return .italian
        }
    }
}

struct PageVocabulary: Sendable {
    let statusColumnTitle: String
    let kindColumnTitle: String
    let areaColumnTitle: String
    let descriptionColumnTitle: String
    let imagesColumnTitle: String
    let historyColumnTitle: String
    let openStatusTitle: String
    let inProgressStatusTitle: String
    let resolvedStatusTitle: String
    let openStatusLegend: String
    let inProgressStatusLegend: String
    let resolvedStatusLegend: String
    let templateOpening: String
    let templateClosing: String
    let openingQuotationMark: String
    let closingQuotationMark: String

    func quoted(_ text: String) -> String {
        openingQuotationMark + text + closingQuotationMark
    }

    static let english = PageVocabulary(
        statusColumnTitle: "Status",
        kindColumnTitle: "Type",
        areaColumnTitle: "Area",
        descriptionColumnTitle: "Description",
        imagesColumnTitle: "Images",
        historyColumnTitle: "History",
        openStatusTitle: "Open",
        inProgressStatusTitle: "In progress",
        resolvedStatusTitle: "Resolved",
        openStatusLegend: "to do",
        inProgressStatusLegend: "someone is working on it",
        resolvedStatusLegend: "done and verified",
        templateOpening: "Log of bugs and requests. Each row has a sequential ID, so that it can be cited in a ticket or a commit, and a status:",
        templateClosing: "To add a row: at the bottom of the table, with the ID after the highest one. Do not change or reuse existing IDs, because they are cited elsewhere. Images go in as thumbnails: a click enlarges them.",
        openingQuotationMark: "“",
        closingQuotationMark: "”"
    )

    static let italian = PageVocabulary(
        statusColumnTitle: "Stato",
        kindColumnTitle: "Tipo",
        areaColumnTitle: "Area",
        descriptionColumnTitle: "Descrizione",
        imagesColumnTitle: "Immagini",
        historyColumnTitle: "Storia",
        openStatusTitle: "Aperto",
        inProgressStatusTitle: "In corso",
        resolvedStatusTitle: "Risolto",
        openStatusLegend: "da fare",
        inProgressStatusLegend: "qualcuno ci sta lavorando",
        resolvedStatusLegend: "fatto e verificato",
        templateOpening: "Registro di bug e richieste. Ogni riga ha un ID progressivo, per poterla citare in un ticket o in un commit, e uno stato:",
        templateClosing: "Per aggiungere una riga: in fondo alla tabella, con l'ID successivo al più alto. Non cambiare né riutilizzare gli ID esistenti, perché sono citati altrove. Le immagini vanno inserite come miniature: un clic le ingrandisce.",
        openingQuotationMark: "«",
        closingQuotationMark: "»"
    )
}
