import Foundation

public enum PageTemplate {
    public static let columnTitles = ColumnKind.allCases.map(\.title)

    public static func storage() -> String {
        let legend = BugStatus.allCases.map { "\($0.macro) \($0.legend)" }
        let introduction = [
            "<p>Registro di bug e richieste. Ogni riga ha un ID progressivo, per poterla citare in un ticket o in un commit, e uno stato:</p>",
            "<p>\(legend.joined(separator: " &nbsp; "))</p>",
            "<p>Per aggiungere una riga: in fondo alla tabella, con l'ID successivo al più alto. Non cambiare né riutilizzare gli ID esistenti, perché sono citati altrove. Le immagini vanno inserite come miniature: un clic le ingrandisce.</p>",
        ]
        let information = "<ac:structured-macro ac:name=\"info\" ac:schema-version=\"1\"><ac:rich-text-body>\(introduction.joined())</ac:rich-text-body></ac:structured-macro>"
        let columns = ColumnKind.allCases.map { "<col style=\"width: \($0.widthPercentage).0%;\" />" }
        let headerCells = ColumnKind.allCases.map { "<th>\($0.title)</th>" }
        let table = "<table class=\"relative-table wrapped\" style=\"width: 100.0%;\"><colgroup>\(columns.joined())</colgroup><tbody><tr>\(headerCells.joined())</tr></tbody></table>"
        return information + table
    }
}
