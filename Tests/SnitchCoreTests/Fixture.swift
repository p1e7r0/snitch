import Foundation
@testable import SnitchCore

enum Fixture {
    static let headerRow = "<tr><th>ID</th><th>Tipo</th><th>Area</th><th>Descrizione</th><th>Immagini</th><th>Stato</th><th>Storia</th></tr>"

    static let openStatus = #"<ac:structured-macro ac:name="status" ac:schema-version="1"><ac:parameter ac:name="colour">Red</ac:parameter><ac:parameter ac:name="title">Aperto</ac:parameter></ac:structured-macro>"#

    static let englishHeaderRow = "<tr><th>ID</th><th>Status</th><th>Type</th><th>Area</th><th>Description</th><th>Images</th><th>History</th></tr>"

    static let englishOpenStatus = #"<ac:structured-macro ac:name="status" ac:schema-version="1"><ac:parameter ac:name="colour">Red</ac:parameter><ac:parameter ac:name="title">Open</ac:parameter></ac:structured-macro>"#

    static let englishPage = "<table><tbody>\(englishHeaderRow)</tbody></table>"

    static let blankRow = "<tr><td><br /></td><td><br /></td><td><br /></td><td><br /></td><td><br /></td><td><div class=\"content-wrapper\"><br /></div></td><td><br /></td></tr>"

    static let lastRow = dataRow(identifier: 4, kind: "Feature", area: "Profilo", description: "Foto del profilo")

    static func dataRow(
        identifier: Int,
        kind: String,
        area: String,
        description: String,
        images: String = "<br />",
        history: String = "<br />"
    ) -> String {
        "<tr><td>\(identifier)</td><td>\(kind)</td><td>\(area)</td><td>\(description)</td><td>\(images)</td><td><div class=\"content-wrapper\">\(openStatus)</div></td><td>\(history)</td></tr>"
    }

    static func renderedRow(identifier: Int, kind: String, area: String, description: String, fileNames: [String]) -> String {
        let images = fileNames.map { fileName in
            "<p><ac:image ac:thumbnail=\"true\" ac:width=\"150\"><ri:attachment ri:filename=\"\(fileName)\" /></ac:image></p>"
        }
        return "<tr><td>\(identifier)</td><td>\(kind)</td><td>\(area)</td><td>\(description)</td><td><div class=\"content-wrapper\">\(images.joined())</div></td><td><div class=\"content-wrapper\">\(openStatus)</div></td><td><br /></td></tr>"
    }

    static let page = [
        #"<ac:structured-macro ac:name="info" ac:schema-version="1"><ac:rich-text-body><p>Registro di bug &amp; richieste.</p></ac:rich-text-body></ac:structured-macro>"#,
        "<table><tbody><tr><th>Nome</th><th>Valore</th></tr><tr><td>a</td><td>b</td></tr></tbody></table>",
        #"<ac:structured-macro ac:name="code"><ac:plain-text-body><![CDATA[<table><tr><th>ID</th><th>Tipo</th><th>Area</th><th>Descrizione</th><th>Immagini</th><th>Stato</th></tr></table>]]></ac:plain-text-body></ac:structured-macro>"#,
        "<!-- <table><tr><th>ID</th></tr></table> -->",
        #"<table class="wrapped"><tbody>"#,
        headerRow,
        dataRow(identifier: 1, kind: "Bug", area: "Elenco ordini", description: "Il totale non si aggiorna"),
        dataRow(
            identifier: 2,
            kind: "Bug",
            area: "Carrello &amp; <strong>pagamenti</strong>",
            description: "“Paga ora” non usa il metodo salvato",
            images: "<table><tbody><tr><td>tabella annidata</td></tr><tr><td>seconda riga</td></tr></tbody></table>",
            history: "Titolo con > dentro <span title=\"a > b\">attributo</span>"
        ),
        dataRow(identifier: 3, kind: "Bug", area: "Elenco ordini", description: "Caricamento molto lento"),
        lastRow,
        blankRow,
        "</tbody></table>",
        "<p>Fine della pagina.</p>",
    ].joined()

    static let pageWithoutBlankRow = page.replacingOccurrences(of: blankRow, with: "")

    static let pageWithoutTable = "<p>Solo testo.</p><table><tbody><tr><th>Nome</th><th>Valore</th></tr></tbody></table>"

    static func makeStore() throws -> ReportStore {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(path: "snitch-tests-\(UUID().uuidString)")
        let store = ReportStore(rootDirectory: rootDirectory)
        try store.prepare()
        return store
    }

    static let destination = PageReference(
        baseURL: URL(string: "https://confluence.example.test")!,
        pageIdentifier: "42"
    )
}
