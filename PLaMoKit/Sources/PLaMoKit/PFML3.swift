import Foundation

public struct GlossaryEntry: Sendable, Equatable, Hashable {
    public var source: String
    public var target: String

    public init(source: String, target: String) {
        self.source = source
        self.target = target
    }
}

public struct TranslationRequest: Sendable, Equatable {
    public var text: String
    public var target: TranslationLanguage
    public var source: TranslationLanguage?
    public var form: OutputForm?
    public var context: String?
    public var glossary: [GlossaryEntry]

    public init(
        text: String,
        target: TranslationLanguage,
        source: TranslationLanguage? = nil,
        form: OutputForm? = nil,
        context: String? = nil,
        glossary: [GlossaryEntry] = []
    ) {
        self.text = text
        self.target = target
        self.source = source
        self.form = form
        self.context = context
        self.glossary = glossary
    }
}

/// Builds the PFML3 prompt used by plamo-3-translate.
///
/// This mirrors `chat_template.jinja` from
/// `pfnet/plamo-3-translate-0.8b-GGUF` exactly:
///
/// ```
/// <bos><|plamo:tag|>dataset<|plamo:msg|>translation
///      [<|plamo:tag|>context<|plamo:msg|>...]
///      [<|plamo:tag|>glossary<|plamo:index|>src<|plamo:item|>dst ...]
///      <|plamo:tag|>input[<|plamo:key|>lang<|plamo:val|>...]<|plamo:msg|>TEXT
///      <|plamo:tag|>output<|plamo:key|>lang<|plamo:val|>TARGET
///      [<|plamo:key|>form<|plamo:val|>plain]<|plamo:msg|>
/// ```
///
/// The leading `<bos>` is intentionally omitted: llama.cpp adds it when
/// tokenizing with `add_special = true`.
public enum PromptBuilder {
    public static func prompt(for request: TranslationRequest) -> String {
        var prompt = "<|plamo:tag|>dataset<|plamo:msg|>translation"

        if let context = request.context, !context.isEmpty {
            prompt += "<|plamo:tag|>context<|plamo:msg|>" + context
        }

        if !request.glossary.isEmpty {
            prompt += "<|plamo:tag|>glossary"
            for entry in request.glossary {
                prompt += "<|plamo:index|>" + entry.source + "<|plamo:item|>" + entry.target
            }
        }

        prompt += "<|plamo:tag|>input"
        if let source = request.source {
            prompt += "<|plamo:key|>lang<|plamo:val|>" + source.rawValue
        }
        prompt += "<|plamo:msg|>" + request.text

        prompt += "<|plamo:tag|>output<|plamo:key|>lang<|plamo:val|>" + request.target.rawValue
        if let form = request.form, request.target == .japanese {
            prompt += "<|plamo:key|>form<|plamo:val|>" + form.rawValue
        }
        prompt += "<|plamo:msg|>"

        return prompt
    }
}
