import Foundation

public struct ConfluencePage: Equatable, Sendable {
    public var identifier: String
    public var title: String
    public var spaceKey: String
    public var version: Int
    public var storage: String

    public init(identifier: String, title: String, spaceKey: String, version: Int, storage: String) {
        self.identifier = identifier
        self.title = title
        self.spaceKey = spaceKey
        self.version = version
        self.storage = storage
    }
}

public enum ConfluenceError: Error, Equatable {
    case network(String)
    case authentication
    case forbidden
    case notFound
    case versionConflict
    case server(status: Int, message: String)
    case unexpectedResponse
}

public protocol ConfluenceService: Sendable {
    func fetchPage(_ pageIdentifier: String) async throws -> ConfluencePage
    func updatePage(_ page: ConfluencePage, storage: String, message: String) async throws
    func attachmentExists(pageIdentifier: String, fileName: String) async throws -> Bool
    func uploadAttachment(pageIdentifier: String, fileName: String, data: Data) async throws
    func createPage(title: String, spaceKey: String, parentIdentifier: String, storage: String) async throws -> String
}
