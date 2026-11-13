import Foundation
import Testing
@testable import SnitchCore

final class StubProtocol: URLProtocol, @unchecked Sendable {
    struct Response {
        let status: Int
        let body: String
    }

    nonisolated(unsafe) static var response = Response(status: 200, body: "{}")
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [Data] = []

    static func reset(status: Int, body: String) {
        response = Response(status: status, body: body)
        requests = []
        bodies = []
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requests.append(request)
        Self.bodies.append(Self.readBody(of: request))
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.response.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.response.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(of request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}

@Suite(.serialized) struct ConfluenceClientTests {
    private func makeClient() -> ConfluenceClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return ConfluenceClient(
            baseURL: URL(string: "https://confluence.example.test")!,
            token: "segreto",
            sessionConfiguration: configuration
        )
    }

    @Test func fetchesPageWithBearerToken() async throws {
        StubProtocol.reset(status: 200, body: #"{"id":"42","title":"Bug","version":{"number":6},"space":{"key":"DEMO"},"body":{"storage":{"value":"<p>ciao</p>"}}}"#)

        let page = try await makeClient().fetchPage("42")

        #expect(page == ConfluencePage(identifier: "42", title: "Bug", spaceKey: "DEMO", version: 6, storage: "<p>ciao</p>"))
        let request = try #require(StubProtocol.requests.first)
        #expect(request.url?.absoluteString == "https://confluence.example.test/rest/api/content/42?expand=body.storage,version,space")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer segreto")
    }

    @Test func sendsNextVersionAsMinorEdit() async throws {
        StubProtocol.reset(status: 200, body: "{}")
        let page = ConfluencePage(identifier: "42", title: "Bug", spaceKey: "DEMO", version: 6, storage: "<p>vecchio</p>")

        try await makeClient().updatePage(page, storage: "<p>nuovo</p>", message: "Snitch")

        let request = try #require(StubProtocol.requests.first)
        let body = try #require(try JSONSerialization.jsonObject(with: StubProtocol.bodies[0]) as? [String: Any])
        let version = try #require(body["version"] as? [String: Any])
        let storage = try #require((body["body"] as? [String: Any])?["storage"] as? [String: Any])
        #expect(request.httpMethod == "PUT")
        #expect(version["number"] as? Int == 7)
        #expect(version["minorEdit"] as? Bool == true)
        #expect(storage["value"] as? String == "<p>nuovo</p>")
        #expect(body["title"] as? String == "Bug")
    }

    @Test func mapsStatusCodesToErrors() async throws {
        let page = ConfluencePage(identifier: "42", title: "Bug", spaceKey: "DEMO", version: 6, storage: "")
        let expectations: [(Int, ConfluenceError)] = [
            (409, .versionConflict),
            (401, .authentication),
            (302, .authentication),
            (403, .forbidden),
            (404, .notFound),
            (500, .server(status: 500, message: "rotto")),
        ]
        for (status, expectedError) in expectations {
            StubProtocol.reset(status: status, body: #"{"message":"rotto"}"#)
            await #expect(throws: expectedError) {
                try await makeClient().updatePage(page, storage: "", message: "")
            }
        }
    }

    @Test func uploadsAttachmentAsMultipartForm() async throws {
        StubProtocol.reset(status: 200, body: "{}")

        try await makeClient().uploadAttachment(pageIdentifier: "42", fileName: "snitch-a-1.png", data: Data("PNG".utf8))

        let request = try #require(StubProtocol.requests.first)
        let body = String(decoding: StubProtocol.bodies[0], as: UTF8.self)
        #expect(request.url?.path == "/rest/api/content/42/child/attachment")
        #expect(request.value(forHTTPHeaderField: "X-Atlassian-Token") == "nocheck")
        #expect(body.contains("name=\"file\"; filename=\"snitch-a-1.png\""))
        #expect(body.contains("\r\n\r\nPNG\r\n"))
    }
}
