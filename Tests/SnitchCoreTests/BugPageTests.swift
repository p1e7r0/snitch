import Foundation
import Testing
@testable import SnitchCore

@Suite struct BugPageTests {
    private func makeRow(_ comment: String, fileName: String, kind: ReportKind = .bug, areaName: String = "Elenco ordini") -> NewBugRow {
        NewBugRow(kind: kind, areaName: areaName, comment: comment, attachmentFileNames: [fileName])
    }

    @Test func findsTheBugTableAndTheAreasAlreadyInUse() {
        let page = BugPage(storage: Fixture.page)

        #expect(page.hasTable)
        #expect(page.language == .italian)
        #expect(page.rowCount == 4)
        #expect(page.areaNames == ["Elenco ordini", "Carrello & pagamenti", "Profilo"])
    }

    @Test func reportsMissingTable() {
        let page = BugPage(storage: Fixture.pageWithoutTable)

        #expect(!page.hasTable)
        #expect(page.language == nil)
        #expect(page.areaNames.isEmpty)
        #expect(throws: BugPageError.tableNotFound) {
            try page.inserting(makeRow("Bug", fileName: "snitch-a-1.png"))
        }
    }

    @Test func appendsRowAfterLastRowLeavingTheRestUntouched() throws {
        let page = BugPage(storage: Fixture.pageWithoutBlankRow)
        let row = NewBugRow(
            kind: .feature,
            areaName: "Profilo & altro",
            comment: "Tooltip <rotto> & lento",
            attachmentFileNames: ["snitch-a-1.png", "snitch-a-2.png"]
        )

        let insertion = try page.inserting(row)

        let expectedRow = Fixture.renderedRow(
            identifier: 5,
            kind: "Feature",
            area: "Profilo &amp; altro",
            description: "Tooltip &lt;rotto&gt; &amp; lento",
            fileNames: ["snitch-a-1.png", "snitch-a-2.png"]
        )
        #expect(insertion.identifier == 5)
        #expect(insertion.storage == Fixture.pageWithoutBlankRow.replacingOccurrences(
            of: Fixture.lastRow,
            with: Fixture.lastRow + expectedRow
        ))
    }

    @Test func fillsTrailingBlankRowInsteadOfLeavingAGap() throws {
        let insertion = try BugPage(storage: Fixture.page).inserting(makeRow("Nuovo bug", fileName: "snitch-b-1.png"))

        let expectedRow = Fixture.renderedRow(
            identifier: 5,
            kind: "Bug",
            area: "Elenco ordini",
            description: "Nuovo bug",
            fileNames: ["snitch-b-1.png"]
        )
        #expect(insertion.identifier == 5)
        #expect(insertion.storage == Fixture.page.replacingOccurrences(of: Fixture.blankRow, with: expectedRow))
    }

    @Test func continuesFromTheHighestIdentifierEvenWhenRowsWereRemoved() throws {
        let storage = Fixture.pageWithoutBlankRow.replacingOccurrences(
            of: Fixture.dataRow(identifier: 3, kind: "Bug", area: "Elenco ordini", description: "Caricamento molto lento"),
            with: ""
        )
        var currentStorage = storage
        var identifiers: [Int] = []
        for index in 1...3 {
            let insertion = try BugPage(storage: currentStorage).inserting(makeRow("Bug \(index)", fileName: "snitch-d\(index)-1.png"))
            currentStorage = insertion.storage
            identifiers.append(insertion.identifier)
        }

        #expect(identifiers == [5, 6, 7])
    }

    @Test func findsIdentifierOfInsertedReportByAttachmentPrefix() throws {
        let insertion = try BugPage(storage: Fixture.page).inserting(makeRow("Bug", fileName: "snitch-e-1.png", areaName: "Nuova area"))
        let updatedPage = BugPage(storage: insertion.storage)

        #expect(updatedPage.containsAttachment(withPrefix: "snitch-e-"))
        #expect(updatedPage.identifier(ofAttachmentPrefix: "snitch-e-") == 5)
        #expect(updatedPage.areaNames == ["Elenco ordini", "Carrello & pagamenti", "Profilo", "Nuova area"])
        #expect(!BugPage(storage: Fixture.page).containsAttachment(withPrefix: "snitch-e-"))
    }

    @Test func insertsIntoBodyWhenHeaderRowLivesInTableHead() throws {
        let storage = "<table><thead>\(Fixture.headerRow)</thead><tbody></tbody></table>"

        let insertion = try BugPage(storage: storage).inserting(makeRow("Bug", fileName: "snitch-f-1.png"))

        let expectedRow = Fixture.renderedRow(identifier: 1, kind: "Bug", area: "Elenco ordini", description: "Bug", fileNames: ["snitch-f-1.png"])
        #expect(insertion.storage == "<table><thead>\(Fixture.headerRow)</thead><tbody>\(expectedRow)</tbody></table>")
    }

    @Test func writesTheStatusInTheLanguageOfTheTableHeader() throws {
        let page = BugPage(storage: Fixture.englishPage)

        let insertion = try page.inserting(makeRow("First", fileName: "snitch-h-1.png", areaName: "Profile"))

        #expect(page.language == .english)
        #expect(insertion.language == .english)
        #expect(insertion.storage == "<table><tbody>\(Fixture.englishHeaderRow)<tr><td>1</td><td><div class=\"content-wrapper\">\(Fixture.englishOpenStatus)</div></td><td>Bug</td><td>Profile</td><td>First</td><td><div class=\"content-wrapper\"><p><ac:image ac:thumbnail=\"true\" ac:width=\"150\"><ri:attachment ri:filename=\"snitch-h-1.png\" /></ac:image></p></div></td><td><br /></td></tr></tbody></table>")
    }

    @Test func ignoresTablesWhoseRequiredColumnsMixLanguages() {
        let storage = "<table><tbody><tr><th>ID</th><th>Stato</th><th>Type</th><th>Area</th><th>Description</th><th>Immagini</th></tr></tbody></table>"

        #expect(!BugPage(storage: storage).hasTable)
    }

    @Test func leavesColumnsTitledInTheOtherLanguageEmpty() throws {
        let headerRow = "<tr><th>Status</th><th>id</th><th>STATO</th><th>Tipo</th><th>Area</th><th>Descrizione</th><th>Immagini</th></tr>"
        let page = BugPage(storage: "<table><tbody>\(headerRow)</tbody></table>")

        let insertion = try page.inserting(makeRow("Bug", fileName: "snitch-i-1.png"))

        #expect(insertion.language == .italian)
        #expect(insertion.storage.contains("\(headerRow)<tr><td><br /></td><td>1</td><td><div class=\"content-wrapper\">\(Fixture.openStatus)</div></td><td>Bug</td>"))
    }

    @Test func englishTemplateProducesAnEmptyEnglishTable() throws {
        let storage = PageTemplate.storage(language: .english)
        let page = BugPage(storage: storage)

        #expect(page.hasTable)
        #expect(page.language == .english)
        #expect(page.rowCount == 0)
        #expect(storage.contains(Fixture.englishHeaderRow))
        #expect(storage.contains("\(Fixture.englishOpenStatus) to do"))
        #expect(PageTemplate.columnTitles(in: .english) == ["ID", "Status", "Type", "Area", "Description", "Images", "History"])
        #expect(BugPage.requiredColumnTitles(in: .english) == ["ID", "Status", "Type", "Area", "Description", "Images"])
    }

    @Test func templateProducesAnEmptyTableReadyForTheFirstRow() throws {
        let storage = PageTemplate.storage(language: .italian)
        let page = BugPage(storage: storage)

        #expect(page.hasTable)
        #expect(page.language == .italian)
        #expect(page.rowCount == 0)
        #expect(storage.contains("<th>ID</th><th>Stato</th><th>Tipo</th><th>Area</th><th>Descrizione</th><th>Immagini</th><th>Storia</th>"))
        #expect(storage.contains("<col style=\"width: 45.0%;\" />"))
        #expect(storage.contains("\(Fixture.openStatus) da fare"))
        #expect(BugPage.requiredColumnTitles(in: .italian) == ["ID", "Stato", "Tipo", "Area", "Descrizione", "Immagini"])

        let insertion = try page.inserting(makeRow("Primo", fileName: "snitch-g-1.png", kind: .feature, areaName: "Profilo"))
        let updatedPage = BugPage(storage: insertion.storage)
        #expect(insertion.identifier == 1)
        #expect(updatedPage.rowCount == 1)
        #expect(updatedPage.areaNames == ["Profilo"])
        #expect(insertion.storage.contains(
            "<tr><td>1</td><td><div class=\"content-wrapper\">\(Fixture.openStatus)</div></td><td>Feature</td><td>Profilo</td><td>Primo</td>"
        ))
    }
}

@Suite struct PageReferenceTests {
    @Test func parsesViewPageAddress() {
        let reference = PageReference(pageAddress: " https://confluence.example.test/pages/viewpage.action?pageId=123456789 ")

        #expect(reference?.baseURL.absoluteString == "https://confluence.example.test")
        #expect(reference?.pageIdentifier == "123456789")
        #expect(reference?.viewURL.absoluteString == "https://confluence.example.test/pages/viewpage.action?pageId=123456789")
    }

    @Test func parsesSpaceAddressWithContextPath() {
        let reference = PageReference(pageAddress: "https://example.test:8443/wiki/spaces/DEMO/pages/123/Bug+demo")

        #expect(reference?.baseURL.absoluteString == "https://example.test:8443/wiki")
        #expect(reference?.pageIdentifier == "123")
    }

    @Test func rejectsAddressesWithoutPageIdentifierOrWithoutEncryption() {
        #expect(PageReference(pageAddress: "https://example.test/display/DEMO/Bug") == nil)
        #expect(PageReference(pageAddress: "http://example.test/pages/viewpage.action?pageId=1") == nil)
        #expect(PageReference(pageAddress: "") == nil)
    }
}
