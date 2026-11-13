import Foundation

public struct PageSummary: Equatable, Sendable {
    public let title: String
    public let hasTable: Bool
    public let rowCount: Int
    public let areaNames: [String]
}

extension ConfluenceService {
    public func summarizePage(_ pageIdentifier: String) async throws -> PageSummary {
        let page = try await fetchPage(pageIdentifier)
        let bugPage = BugPage(storage: page.storage)
        return PageSummary(
            title: page.title,
            hasTable: bugPage.hasTable,
            rowCount: bugPage.rowCount,
            areaNames: bugPage.areaNames
        )
    }
}
