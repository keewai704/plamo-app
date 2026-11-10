import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import KotobaCore
import XCTest

/// Replies with canned responses and records what was sent.
final class StubServer: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [(Int, String)]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [(Int, String)]) {
        self.responses = responses
    }

    func handle(_ request: URLRequest) throws -> (Data, URLResponse) {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
        let (status, body) = responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }

    func client(apiKey: String = "secret") -> TranslationClient {
        TranslationClient(serverURL: "http://server:8000/", apiKey: apiKey) { [self] in try handle($0) }
    }

    func body(at index: Int = 0) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: requests[index].httpBody!) as? [String: Any])
    }
}

func completion(_ content: String, finishReason: String = "stop") -> (Int, String) {
    (200, #"{"choices":[{"message":{"content":"\#(content)"},"finish_reason":"\#(finishReason)"}]}"#)
}

final class TranslationClientTests: XCTestCase {
    func testSendsTheRequestTheModelExpects() async throws {
        let server = StubServer([completion("Hello")])

        let translated = try await server.client().translate("こんにちは", target: "en")

        XCTAssertEqual(translated, "Hello")
        let request = server.requests[0]
        XCTAssertEqual(request.url?.absoluteString, "http://server:8000/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        let body = try server.body()
        XCTAssertEqual(body["chat_template_kwargs"] as? [String: String], ["target_lang": "en"])
        XCTAssertEqual(body["stop"] as? [String], ["<|plamo:tag|>", "<|plamo:bos|>"])
        XCTAssertEqual(body["temperature"] as? Int, 0)
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages, [["role": "user", "content": "こんにちは"]])
    }

    func testAutoTargetOmitsLanguage() async throws {
        let server = StubServer([completion("x")])
        _ = try await server.client().translate("text", target: Languages.auto, form: .polite)
        XCTAssertEqual(try server.body()["chat_template_kwargs"] as? [String: String], [:])
    }

    func testFormIsSentOnlyForJapanese() async throws {
        let server = StubServer([completion("x"), completion("y")])
        _ = try await server.client().translate("text", target: "ja", form: .polite)
        _ = try await server.client().translate("text", target: "en", form: .polite)
        XCTAssertEqual(try server.body(at: 0)["chat_template_kwargs"] as? [String: String], ["target_lang": "ja", "form": "polite"])
        XCTAssertEqual(try server.body(at: 1)["chat_template_kwargs"] as? [String: String], ["target_lang": "en"])
    }

    func testNoAuthorizationHeaderWithoutKey() async throws {
        let server = StubServer([completion("x")])
        _ = try await server.client(apiKey: "").translate("text", target: "ja")
        XCTAssertNil(server.requests[0].value(forHTTPHeaderField: "Authorization"))
    }

    func testTruncatedOutputIsAnError() async {
        let server = StubServer([completion("partial", finishReason: "length")])
        await assertThrows(.truncated) { _ = try await server.client().translate("text", target: "ja") }
    }

    func testRejectedKey() async {
        let server = StubServer([(401, "{}")])
        await assertThrows(.unauthorized) { _ = try await server.client().translate("text", target: "ja") }
    }

    func testServerMessageIsSurfaced() async {
        let server = StubServer([(400, #"{"error":{"message":"bad input"}}"#)])
        await assertThrows(.server("bad input")) { _ = try await server.client().translate("text", target: "ja") }
    }

    func testUnreachableServer() async {
        let client = TranslationClient(serverURL: "http://server", apiKey: "") { _ in throw URLError(.cannotConnectToHost) }
        await assertThrows(.unreachable) { _ = try await client.translate("text", target: "ja") }
    }

    func testInvalidURLNeverReachesTheNetwork() async {
        let client = TranslationClient(serverURL: "not a url", apiKey: "") { _ in
            XCTFail("sent a request")
            throw URLError(.badURL)
        }
        await assertThrows(.invalidURL) { _ = try await client.translate("text", target: "ja") }
    }

    func testStatusIsReadyWhenWeightsAreLoaded() async {
        let server = StubServer([(200, #"{"status":"ok"}"#), (200, #"{"is_sleeping":false}"#)])
        let status = await server.client().status()
        XCTAssertEqual(status, .ready)
        XCTAssertEqual(server.requests.map(\.url?.path), ["/health", "/props"])
        XCTAssertEqual(server.requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    }

    func testStatusIsSleepingWhenWeightsWereReleased() async {
        let server = StubServer([(200, "{}"), (200, #"{"is_sleeping":true}"#)])
        let status = await server.client().status()
        XCTAssertEqual(status, .sleeping)
    }

    func testStatusIsReadyOnAVLLMServer() async {
        let server = StubServer([(200, "{}"), (404, "{}"), (200, #"{"data":[]}"#)])
        let status = await server.client().status()
        XCTAssertEqual(status, .ready)
        XCTAssertEqual(server.requests.map(\.url?.path), ["/health", "/props", "/v1/models"])
        XCTAssertEqual(server.requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    }

    func testStatusReportsAKeyRejectedByAVLLMServer() async {
        let server = StubServer([(200, "{}"), (404, "{}"), (401, "{}")])
        let status = await server.client().status()
        XCTAssertEqual(status, .unauthorized)
    }

    func testStatusIsLoadingDuring503() async {
        let server = StubServer([(503, "{}")])
        let status = await server.client().status()
        XCTAssertEqual(status, .loading)
        XCTAssertEqual(server.requests.count, 1)
    }

    func testStatusReportsARejectedKey() async {
        let server = StubServer([(200, "{}"), (401, "{}")])
        let status = await server.client().status()
        XCTAssertEqual(status, .unauthorized)
        XCTAssertEqual(status.error, .unauthorized)
    }

    func testStatusReportsAnUnreachableServer() async {
        let client = TranslationClient(serverURL: "http://server", apiKey: "") { _ in throw URLError(.cannotConnectToHost) }
        let status = await client.status()
        XCTAssertEqual(status, .unreachable)
    }

    func testLanguageListHasEveryModelLanguage() {
        XCTAssertEqual(Languages.codes.count, 53)
        XCTAssertEqual(Languages.codes.prefix(2), ["ja", "en"])
    }

    private func assertThrows(
        _ expected: TranslationError,
        _ body: () async throws -> Void,
        line: UInt = #line
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected)", line: line)
        } catch {
            XCTAssertEqual(error as? TranslationError, expected, line: line)
        }
    }
}
