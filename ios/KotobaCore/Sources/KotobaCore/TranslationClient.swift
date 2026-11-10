import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum OutputForm: String, CaseIterable, Sendable {
    case polite
    case plain
}

public enum ServerStatus: String, Sendable {
    case ready
    case sleeping
    case loading
    case unauthorized
    case unreachable

    /// A status that means the settings or the network need attention.
    public var error: TranslationError? {
        switch self {
        case .unauthorized: .unauthorized
        case .unreachable: .unreachable
        case .ready, .sleeping, .loading: nil
        }
    }
}

public enum TranslationError: LocalizedError, Equatable {
    case invalidURL
    case unreachable
    case unauthorized
    case truncated
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: "サーバー URL が正しくありません"
        case .unreachable: "サーバーに接続できません"
        case .unauthorized: "API キーが正しくありません"
        case .truncated: "訳文が長すぎて途中で打ち切られました"
        case let .server(message): message
        }
    }
}

/// Talks to the OpenAI-compatible API of llama-server or vLLM.
public struct TranslationClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private static let maxOutputTokens = 2048
    private static let timeout: TimeInterval = 120

    private let serverURL: String
    private let apiKey: String
    private let transport: Transport

    public init(
        serverURL: String,
        apiKey: String,
        transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }
    ) {
        self.serverURL = serverURL
        self.apiKey = apiKey
        self.transport = transport
    }

    /// Translates one chunk from `TextChunker`.
    public func translate(_ text: String, target: String, form: OutputForm? = nil) async throws -> String {
        var options: [String: String] = [:]
        if target != Languages.auto { options["target_lang"] = target }
        if target == "ja", let form { options["form"] = form.rawValue }

        var request = try makeRequest(path: "/v1/chat/completions")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(
                messages: [.init(role: "user", content: text)],
                chatTemplateKwargs: options,
                temperature: 0,
                maxTokens: Self.maxOutputTokens,
                stop: ["<|plamo:tag|>", "<|plamo:bos|>"]
            )
        )

        let data = try await send(request)
        guard let choice = try JSONDecoder().decode(ChatResponse.self, from: data).choices.first else {
            throw TranslationError.server("サーバーの応答が正しくありません")
        }
        if choice.finishReason == "length" { throw TranslationError.truncated }
        return choice.message.content
    }

    /// Reports whether the weights are loaded. Neither request wakes a sleeping server.
    public func status() async -> ServerStatus {
        do {
            let (_, health) = try await exchange(makeRequest(path: "/health"))
            if health == 503 { return .loading }
            guard (200..<300).contains(health) else { return .unreachable }

            let (data, props) = try await exchange(makeRequest(path: "/props"))
            if props == 401 { return .unauthorized }
            if props == 404 { return try await vllmStatus() }
            guard (200..<300).contains(props) else { return .unreachable }
            return try JSONDecoder().decode(Props.self, from: data).isSleeping ? .sleeping : .ready
        } catch {
            return .unreachable
        }
    }

    /// vLLM has no `/props` and holds the weights for as long as it answers.
    private func vllmStatus() async throws -> ServerStatus {
        let (_, models) = try await exchange(makeRequest(path: "/v1/models"))
        if models == 401 { return .unauthorized }
        return (200..<300).contains(models) ? .ready : .unreachable
    }

    private func makeRequest(path: String) throws -> URLRequest {
        var base = serverURL.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        guard
            let url = URL(string: base + path),
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            url.host != nil
        else {
            throw TranslationError.invalidURL
        }
        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, status) = try await exchange(request)
        if status == 401 { throw TranslationError.unauthorized }
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error.message
            throw TranslationError.server(message ?? "サーバーエラー (\(status))")
        }
        return data
    }

    private func exchange(_ request: URLRequest) async throws -> (Data, Int) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is URLError {
            throw TranslationError.unreachable
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw TranslationError.unreachable }
        return (data, status)
    }
}

private struct ChatRequest: Encodable {
    struct Message: Encodable {
        var role: String
        var content: String
    }

    var model = "plamo-3-translate"
    var messages: [Message]
    var chatTemplateKwargs: [String: String]
    var temperature: Double
    var maxTokens: Int
    var stop: [String]

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stop
        case chatTemplateKwargs = "chat_template_kwargs"
        case maxTokens = "max_tokens"
    }
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String
        }

        var message: Message
        var finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    var choices: [Choice]
}

private struct Props: Decodable {
    var isSleeping: Bool

    enum CodingKeys: String, CodingKey {
        case isSleeping = "is_sleeping"
    }
}

private struct ErrorResponse: Decodable {
    struct Detail: Decodable {
        var message: String
    }

    var error: Detail
}
