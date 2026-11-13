import Foundation
import Testing
@testable import SnitchCore

actor FakeConfluence: ConfluenceService {
    var page: ConfluencePage
    var attachments: [String: Data] = [:]
    var uploadCount = 0
    var updateCount = 0
    private var concurrentEdit: (@Sendable (String) -> String)?
    private var shouldLoseNextUpdateResponse = false

    init(storage: String) {
        page = ConfluencePage(identifier: "42", title: "Bug", spaceKey: "DEMO", version: 6, storage: storage)
    }

    func simulateConcurrentEdit(_ edit: @escaping @Sendable (String) -> String) {
        concurrentEdit = edit
    }

    func loseNextUpdateResponse() {
        shouldLoseNextUpdateResponse = true
    }

    func fetchPage(_ pageIdentifier: String) async throws -> ConfluencePage {
        page
    }

    func updatePage(_ page: ConfluencePage, storage: String, message: String) async throws {
        if let edit = concurrentEdit {
            concurrentEdit = nil
            self.page.storage = edit(self.page.storage)
            self.page.version += 1
        }
        guard page.version == self.page.version else {
            throw ConfluenceError.versionConflict
        }
        self.page.storage = storage
        self.page.version += 1
        updateCount += 1
        if shouldLoseNextUpdateResponse {
            shouldLoseNextUpdateResponse = false
            throw ConfluenceError.network("timeout")
        }
    }

    func attachmentExists(pageIdentifier: String, fileName: String) async throws -> Bool {
        attachments[fileName] != nil
    }

    func uploadAttachment(pageIdentifier: String, fileName: String, data: Data) async throws {
        attachments[fileName] = data
        uploadCount += 1
    }

    func createPage(title: String, spaceKey: String, parentIdentifier: String, storage: String) async throws -> String {
        "43"
    }
}

@Suite struct ReportSubmitterTests {
    private func makeQueuedReport() throws -> (Report, ReportStore) {
        let store = try Fixture.makeStore()
        let draft = try store.createDraft()
        let fileNames = [store.imageFileName(for: draft, index: 1), store.imageFileName(for: draft, index: 2)]
        for fileName in fileNames {
            try Data("immagine".utf8).write(to: draft.directory.appending(path: fileName))
        }
        let report = try store.enqueue(
            draft,
            kind: .bug,
            areaName: "Carrello pagamenti",
            comment: "Il tooltip segue lo scroll",
            imageFileNames: fileNames,
            destination: Fixture.destination
        )
        return (report, store)
    }

    private func expectedRow(identifier: Int, for report: Report) -> String {
        Fixture.renderedRow(
            identifier: identifier,
            kind: "Bug",
            area: "Carrello pagamenti",
            description: "Il tooltip segue lo scroll",
            fileNames: report.imageFileNames
        )
    }

    @Test func uploadsScreenshotsAndInsertsRow() async throws {
        let (report, store) = try makeQueuedReport()
        let confluence = FakeConfluence(storage: Fixture.pageWithoutBlankRow)

        let result = try await ReportSubmitter(service: confluence).submit(report, imageDirectory: store.directory(for: report))

        #expect(result == SubmissionResult(identifier: 5))
        #expect(await confluence.attachments.keys.sorted() == report.imageFileNames.sorted())
        #expect(await confluence.page.storage == Fixture.pageWithoutBlankRow.replacingOccurrences(
            of: Fixture.lastRow,
            with: Fixture.lastRow + expectedRow(identifier: 5, for: report)
        ))
        #expect(await confluence.page.version == 7)
    }

    @Test func keepsChangesPublishedByOthersInTheMeantime() async throws {
        let (report, store) = try makeQueuedReport()
        let confluence = FakeConfluence(storage: Fixture.pageWithoutBlankRow)
        let otherRow = Fixture.dataRow(identifier: 5, kind: "Bug", area: "Profilo", description: "Bug di un collega")
        await confluence.simulateConcurrentEdit { storage in
            storage.replacingOccurrences(of: Fixture.lastRow, with: Fixture.lastRow + otherRow)
        }

        let result = try await ReportSubmitter(service: confluence).submit(report, imageDirectory: store.directory(for: report))

        #expect(result.identifier == 6)
        let storage = await confluence.page.storage
        #expect(storage.contains(otherRow + expectedRow(identifier: 6, for: report)))
        #expect(await confluence.uploadCount == 2)
    }

    @Test func doesNotInsertTwiceWhenTheResponseIsLost() async throws {
        let (report, store) = try makeQueuedReport()
        let confluence = FakeConfluence(storage: Fixture.pageWithoutBlankRow)
        let submitter = ReportSubmitter(service: confluence)
        await confluence.loseNextUpdateResponse()

        await #expect(throws: ConfluenceError.network("timeout")) {
            try await submitter.submit(report, imageDirectory: store.directory(for: report))
        }
        let result = try await submitter.submit(report, imageDirectory: store.directory(for: report))

        #expect(result == SubmissionResult(identifier: 5))
        #expect(await confluence.updateCount == 1)
        #expect(await confluence.uploadCount == 2)
        let storage = await confluence.page.storage
        #expect(storage.components(separatedBy: "Il tooltip segue lo scroll").count == 2)
    }

    @Test func leavesPageAndAttachmentsAloneWhenTheTableIsMissing() async throws {
        let (report, store) = try makeQueuedReport()
        let confluence = FakeConfluence(storage: Fixture.pageWithoutTable)

        await #expect(throws: BugPageError.tableNotFound) {
            try await ReportSubmitter(service: confluence).submit(report, imageDirectory: store.directory(for: report))
        }

        #expect(await confluence.uploadCount == 0)
        #expect(await confluence.page.storage == Fixture.pageWithoutTable)
    }
}

@Suite struct PageSummaryTests {
    @Test func summarizesTitleRowsAndAreasOfThePage() async throws {
        let summary = try await FakeConfluence(storage: Fixture.page).summarizePage("42")

        #expect(summary == PageSummary(
            title: "Bug",
            hasTable: true,
            rowCount: 4,
            areaNames: ["Elenco ordini", "Carrello & pagamenti", "Profilo"]
        ))
    }

    @Test func summarizesPageWithoutTable() async throws {
        let summary = try await FakeConfluence(storage: Fixture.pageWithoutTable).summarizePage("42")

        #expect(summary == PageSummary(title: "Bug", hasTable: false, rowCount: 0, areaNames: []))
    }
}

@Suite struct ReportStoreTests {
    @Test func keepsQueuedReportsInCreationOrderAndRemovesThemWithTheirScreenshots() throws {
        let store = try Fixture.makeStore()
        let firstDraft = try store.createDraft()
        let secondDraft = try store.createDraft()
        let abandonedDraft = try store.createDraft()
        let earlier = Date(timeIntervalSince1970: 1_000)
        let later = Date(timeIntervalSince1970: 2_000)

        let second = try store.enqueue(secondDraft, kind: .feature, areaName: "Profilo", comment: "Secondo", imageFileNames: [], destination: Fixture.destination, now: later)
        let first = try store.enqueue(firstDraft, kind: .bug, areaName: "Elenco ordini", comment: "Primo", imageFileNames: [], destination: Fixture.destination, now: earlier)
        store.purgeAbandonedDrafts()

        #expect(store.pendingReports() == [first, second])
        #expect(!FileManager.default.fileExists(atPath: abandonedDraft.directory.path))

        store.remove(first)

        #expect(store.pendingReports() == [second])
        #expect(!FileManager.default.fileExists(atPath: firstDraft.directory.path))
    }

    @Test func readsReportsQueuedBeforeTheTypeExistedAsBugs() throws {
        let store = try Fixture.makeStore()
        let draft = try store.createDraft()
        let legacyReport = #"{"identifier":"\#(draft.identifier)","createdAt":"2026-11-12T18:45:01Z","comment":"Vecchio","areaName":"Catalogo","imageFileNames":[],"destination":{"baseURL":"https://confluence.example.test","pageIdentifier":"42"}}"#
        try Data(legacyReport.utf8).write(to: draft.directory.appending(path: "report.json"))

        let reports = store.pendingReports()

        #expect(reports.map(\.kind) == [.bug])
        #expect(reports.map(\.comment) == ["Vecchio"])
    }
}
