import Foundation
import PLaMoKit

#if canImport(llama)
import llama

/// llama.cpp is initialized once per process. The global is lazy and
/// thread-safe; `llama_backend_init()` also registers the Metal backend.
private final class LlamaBackend {
    init() {
        llama_backend_init()
    }
}

private let sharedBackend = LlamaBackend()

/// Local translation engine backed by llama.cpp and a GGUF model.
///
/// The upstream `llama.xcframework` ships a device (ios-arm64) slice only.
/// Simulator builds therefore compile the stub below and use
/// `MockTranslationEngine` instead.
public final class LlamaEngine: TranslationEngine, @unchecked Sendable {
    public static var isSupported: Bool { true }

    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    private let options: EngineOptions
    private let lock = NSLock()

    public init(modelURL: URL, options: EngineOptions = .appDefault) throws {
        _ = sharedBackend

        var modelParameters = llama_model_default_params()
        modelParameters.n_gpu_layers = Int32(options.gpuLayers)

        guard let model = modelURL.path.withCString({ path in
            llama_model_load_from_file(path, modelParameters)
        }) else {
            throw TranslationEngineError.modelLoadFailed(modelURL.lastPathComponent)
        }

        var contextParameters = llama_context_default_params()
        contextParameters.n_ctx = UInt32(options.contextLength)
        contextParameters.n_batch = UInt32(options.batchSize)
        contextParameters.n_ubatch = UInt32(options.microBatchSize)
        contextParameters.n_threads = Int32(options.resolvedThreadCount)
        contextParameters.n_threads_batch = Int32(options.resolvedThreadCount)
        contextParameters.type_k = GGML_TYPE_Q8_0
        contextParameters.type_v = GGML_TYPE_Q8_0
        contextParameters.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO
        contextParameters.offload_kqv = true

        guard let context = llama_init_from_model(model, contextParameters) else {
            llama_model_free(model)
            throw TranslationEngineError.contextCreationFailed
        }
        guard let vocab = llama_model_get_vocab(model) else {
            llama_free(context)
            llama_model_free(model)
            throw TranslationEngineError.contextCreationFailed
        }

        self.model = model
        self.context = context
        self.vocab = vocab
        self.options = options
    }

    deinit {
        llama_free(context)
        llama_model_free(model)
    }

    public func translate(_ request: TranslationRequest) async throws -> String {
        try await Task.detached(priority: .userInitiated) { [self] in
            try generate(request)
        }.value
    }

    private func generate(_ request: TranslationRequest) throws -> String {
        lock.lock()
        defer { lock.unlock() }

        if let memory = llama_get_memory(context) {
            llama_memory_clear(memory, true)
        }

        let prompt = PromptBuilder.prompt(for: request)
        var tokens = try tokenize(prompt)
        guard !tokens.isEmpty else { throw TranslationEngineError.tokenizationFailed }
        guard tokens.count + options.maxNewTokens <= options.contextLength else {
            throw TranslationEngineError.inputTooLong
        }

        var status = llama_decode(context, llama_batch_get_one(&tokens, Int32(tokens.count)))
        guard status == 0 else { throw TranslationEngineError.decodeFailed(status) }

        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()),
              let greedy = llama_sampler_init_greedy() else {
            throw TranslationEngineError.samplerCreationFailed
        }
        defer { llama_sampler_free(sampler) }
        llama_sampler_chain_add(sampler, greedy)

        var pending = Data()
        var output = ""

        for _ in 0..<Int(options.maxNewTokens) {
            try Task.checkCancellation()

            let token = llama_sampler_sample(sampler, context, -1)
            llama_sampler_accept(sampler, token)
            if llama_vocab_is_eog(vocab, token) { break }

            appendPiece(for: token, to: &pending, output: &output)

            var next = token
            status = llama_decode(context, llama_batch_get_one(&next, 1))
            guard status == 0 else { throw TranslationEngineError.decodeFailed(status) }
        }

        if !pending.isEmpty {
            output += String(decoding: pending, as: UTF8.self)
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokenize(_ text: String) throws -> [llama_token] {
        let byteCount = text.utf8.count
        var tokens = [llama_token](repeating: 0, count: max(64, byteCount + 16))
        let tokenCount = text.withCString { pointer in
            llama_tokenize(
                vocab,
                pointer,
                Int32(byteCount),
                &tokens,
                Int32(tokens.count),
                true,
                true
            )
        }
        guard tokenCount >= 0 else { throw TranslationEngineError.tokenizationFailed }
        return Array(tokens.prefix(Int(tokenCount)))
    }

    private func appendPiece(for token: llama_token, to pending: inout Data, output: inout String) {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        guard length > 0 else { return }

        pending.append(contentsOf: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) })
        // A token can end in the middle of a multi-byte character, so only
        // flush when the whole pending buffer is valid UTF-8.
        if let decoded = String(data: pending, encoding: .utf8) {
            output += decoded
            pending.removeAll(keepingCapacity: true)
        }
    }
}

#elseif LLAMA_REQUIRED

#error("llama.xcframework is required for device builds. Run 'make fetch-llama'.")

#else

public final class LlamaEngine: TranslationEngine, @unchecked Sendable {
    public static var isSupported: Bool { false }

    public init(modelURL: URL, options: EngineOptions = .appDefault) throws {
        throw TranslationEngineError.unsupportedPlatform
    }

    public func translate(_ request: TranslationRequest) async throws -> String {
        throw TranslationEngineError.unsupportedPlatform
    }
}

#endif
