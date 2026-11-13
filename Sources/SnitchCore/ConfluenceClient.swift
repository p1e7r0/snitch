import Foundation

public final class ConfluenceClient: ConfluenceService {
    private let baseURL: URL
    private let token: String
    private let session: URLSession

    public init(baseURL: URL, token: String, sessionConfiguration: URLSessionConfiguration = .ephemeral) {
        self.baseURL = baseURL
        self.token = token
        sessionConfiguration.timeoutIntervalForRequest = 30
        sessionConfiguration.timeoutIntervalForResource = 180
        sessionConfiguration.httpShouldSetCookies = false
        sessionConfiguration.httpCookieAcceptPolicy = .never
        sessionConfiguration.urlCache = nil
        self.session = URLSession(configuration: sessionConfiguration, delegate: RedirectBlocker(), delegateQueue: nil)
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    public func fetchPage(_ pageIdentifier: String) async throws -> ConfluencePage {
        let request = makeRequest(
            method: "GET",
            path: "rest/api/content/\(pageIdentifier)",
            queryItems: [URLQueryItem(name: "expand", value: "body.storage,version,space")]
        )
        let payload = try decode(ContentPayload.self, from: try await perform(request))
        guard let version = payload.version, let space = payload.space, let body = payload.body else {
            throw ConfluenceError.unexpectedResponse
        }
        return ConfluencePage(
            identifier: payload.identifier,
            title: payload.title,
            spaceKey: space.key,
            version: version.number,
            storage: body.storage.value
        )
    }

    public func updatePage(_ page: ConfluencePage, storage: String, message: String) async throws {
        let request = try makeJSONRequest(method: "PUT", path: "rest/api/content/\(page.identifier)", body: [
            "id": page.identifier,
            "type": "page",
            "title": page.title,
            "version": ["number": page.version + 1, "minorEdit": true, "message": message],
            "body": Self.storageBody(storage),
        ])
        _ = try await perform(request)
    }

    public func attachmentExists(pageIdentifier: String, fileName: String) async throws -> Bool {
        let request = makeRequest(
            method: "GET",
            path: "rest/api/content/\(pageIdentifier)/child/attachment",
            queryItems: [URLQueryItem(name: "filename", value: fileName), URLQueryItem(name: "limit", value: "1")]
        )
        let payload = try decode(ResultsPayload.self, from: try await perform(request))
        return !payload.results.isEmpty
    }

    public func uploadAttachment(pageIdentifier: String, fileName: String, data: Data) async throws {
        var request = makeRequest(method: "POST", path: "rest/api/content/\(pageIdentifier)/child/attachment")
        let boundary = "snitch-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"minorEdit\"\r\n\r\ntrue\r\n".utf8))
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\nContent-Type: image/png\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("nocheck", forHTTPHeaderField: "X-Atlassian-Token")
        _ = try await perform(request)
    }

    public func createPage(title: String, spaceKey: String, parentIdentifier: String, storage: String) async throws -> String {
        let request = try makeJSONRequest(method: "POST", path: "rest/api/content", body: [
            "type": "page",
            "title": title,
            "space": ["key": spaceKey],
            "ancestors": [["id": parentIdentifier]],
            "body": Self.storageBody(storage),
        ])
        return try decode(ContentPayload.self, from: try await perform(request)).identifier
    }

    private func makeRequest(method: String, path: String, queryItems: [URLQueryItem] = []) -> URLRequest {
        var url = baseURL.appending(path: path)
        if !queryItems.isEmpty {
            url = url.appending(queryItems: queryItems)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func makeJSONRequest(method: String, path: String, body: [String: Any]) throws -> URLRequest {
        var request = makeRequest(method: method, path: path)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private static func storageBody(_ storage: String) -> [String: Any] {
        ["storage": ["value": storage, "representation": "storage"]]
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ConfluenceError.network(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConfluenceError.unexpectedResponse
        }
        switch httpResponse.statusCode {
        case 200..<300:
            return data
        case 300..<400, 401:
            throw ConfluenceError.authentication
        case 403:
            throw ConfluenceError.forbidden
        case 404:
            throw ConfluenceError.notFound
        case 409:
            throw ConfluenceError.versionConflict
        default:
            let message = (try? JSONDecoder().decode(ErrorPayload.self, from: data))?.message ?? ""
            throw ConfluenceError.server(status: httpResponse.statusCode, message: message)
        }
    }

    private func decode<Payload: Decodable>(_ type: Payload.Type, from data: Data) throws -> Payload {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ConfluenceError.unexpectedResponse
        }
    }
}

private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

private struct ContentPayload: Decodable {
    struct Version: Decodable {
        let number: Int
    }

    struct Space: Decodable {
        let key: String
    }

    struct Body: Decodable {
        struct Storage: Decodable {
            let value: String
        }

        let storage: Storage
    }

    let identifier: String
    let title: String
    let version: Version?
    let space: Space?
    let body: Body?

    enum CodingKeys: String, CodingKey {
        case identifier = "id"
        case title
        case version
        case space
        case body
    }
}

private struct ResultsPayload: Decodable {
    struct Item: Decodable {}

    let results: [Item]
}

private struct ErrorPayload: Decodable {
    let message: String?
}
