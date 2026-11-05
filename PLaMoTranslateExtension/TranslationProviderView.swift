import Foundation
import SwiftUI
import TranslationUIProvider
import UIKit
import PLaMoKit

@MainActor
struct TranslationProviderView: View {
    let context: TranslationUIProviderContext

    @State private var viewModel = TranslationViewModel()
    @State private var phase: Phase = .loading
    @State private var inputText = ""

    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(inputText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    result
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .padding(16)
        .task { await start() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("Kotoba", systemImage: "character.bubble")
                .font(.headline)
            Spacer()
            if viewModel.isTranslating {
                ProgressView().controlSize(.small)
            }
            Button {
                context.expandSheet()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("拡大")
        }
    }

    @ViewBuilder
    private var result: some View {
        switch phase {
        case .loading:
            Text("モデルを読み込み中…")
                .foregroundStyle(.secondary)

        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)

        case .ready:
            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            } else {
                Text(viewModel.output.isEmpty && viewModel.isTranslating ? "翻訳中…" : viewModel.output)
                    .font(.body)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("provider.output")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                UIPasteboard.general.string = viewModel.output
                context.finish(translation: nil)
            } label: {
                Label("コピー", systemImage: "doc.on.doc")
            }
            .disabled(viewModel.output.isEmpty)
            .accessibilityIdentifier("provider.copy")

            Spacer()

            Button {
                context.finish(translation: AttributedString(viewModel.output))
            } label: {
                Label("置き換え", systemImage: "arrow.turn.down.left")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.output.isEmpty || !context.allowsReplacement)
            .accessibilityIdentifier("provider.replace")

            Button("閉じる") {
                context.finish(translation: nil)
            }
            .buttonStyle(.bordered)
        }
    }

    private func start() async {
        context.expandSheet()

        inputText = context.inputText.map { NSAttributedString($0).string } ?? ""
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .failed("テキストが選択されていません。")
            return
        }

        viewModel.input = inputText
        viewModel.updateSuggestedTarget()

        let store = ModelStore.shared()
        guard let variant = store.preferredInstalledVariant() else {
            phase = .failed("モデルがありません。Kotoba アプリでモデルを取得してください。")
            return
        }

        do {
            let engine = try await Task.detached(priority: .userInitiated) {
                try LlamaEngine(modelURL: store.url(for: variant), options: .translationExtension)
            }.value
            phase = .ready
            await viewModel.translate(using: engine, maxCharacters: 480)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
