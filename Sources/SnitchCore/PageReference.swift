import Foundation

public struct PageReference: Codable, Equatable, Sendable {
    public let baseURL: URL
    public let pageIdentifier: String

    public init(baseURL: URL, pageIdentifier: String) {
        self.baseURL = baseURL
        self.pageIdentifier = pageIdentifier
    }

    public init?(pageAddress: String) {
        let trimmedAddress = pageAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmedAddress),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty else {
            return nil
        }
        let path = components.path
        let contextPath: String
        let identifier: String
        if let viewPageRange = path.range(of: "/pages/viewpage.action"),
           let value = components.queryItems?.first(where: { $0.name == "pageId" })?.value {
            contextPath = String(path[..<viewPageRange.lowerBound])
            identifier = value
        } else if let match = path.firstMatch(of: #/^(.*?)/spaces/[^/]+/pages/(\d+)(?:/.*)?$/#) {
            contextPath = String(match.1)
            identifier = String(match.2)
        } else {
            return nil
        }
        guard !identifier.isEmpty, identifier.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return nil
        }
        var baseComponents = URLComponents()
        baseComponents.scheme = "https"
        baseComponents.host = host
        baseComponents.port = components.port
        baseComponents.path = contextPath
        guard let baseURL = baseComponents.url else {
            return nil
        }
        self.baseURL = baseURL
        self.pageIdentifier = identifier
    }

    public var host: String? {
        baseURL.host
    }

    public var viewURL: URL {
        baseURL
            .appending(path: "pages/viewpage.action")
            .appending(queryItems: [URLQueryItem(name: "pageId", value: pageIdentifier)])
    }
}
