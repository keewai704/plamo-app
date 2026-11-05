import SwiftUI
import PLaMoKit
import UIKit

struct TranslateView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    EngineStatusView(model: appModel)
                    InputSection(model: appModel)
                    ControlRow(model: appModel)
                    OutputSection(model: appModel)
                    AttributionFooter()
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Kotoba")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        appModel.isShowingModelSheet = true
                    } label: {
                        Image(systemName: "cube.box")
                    }
                    .accessibilityLabel("モデル設定")
                    .accessibilityIdentifier("model.open")
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("翻訳") {
                        Task { await appModel.translate() }
                    }
                    .disabled(!appModel.translation.canTranslate || appModel.engineState != .ready)
                    .accessibilityIdentifier("translate.run.keyboard")
                }
            }
        }
    }
}

private struct EngineStatusView: View {
    @Bindable var model: AppModel

    var body: some View {
        switch model.engineState {
        case .noModel:
            VStack(alignment: .leading, spacing: 8) {
                Label("モデルが未設定です", systemImage: "arrow.down.circle")
                    .font(.subheadline.weight(.semibold))
                Text("Q3_K_M（約486MB）をダウンロードするか、GGUF ファイルを読み込んでください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("モデルを設定") {
                    model.isShowingModelSheet = true
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("model.setup")
            }
            .cardStyle()

        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("モデルを読み込み中…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .cardStyle()

        case .ready:
            if model.isUsingMockEngine {
                Label("この環境ではモックエンジンで動作しています。実機では llama.cpp を使います。", systemImage: "testtube.2")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .cardStyle()
            }

        case let .failed(message):
            VStack(alignment: .leading, spacing: 6) {
                Label("エンジンを初期化できませんでした", systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("再読み込み") {
                    Task { await model.loadEngine() }
                }
                .buttonStyle(.bordered)
            }
            .cardStyle()
        }
    }
}

private struct InputSection: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("原文")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("翻訳したい文章を入力", text: $model.translation.input, axis: .vertical)
                .lineLimit(3...8)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("translate.input")
        }
        .cardStyle()
        .onChange(of: model.translation.input) { _, _ in
            model.translation.updateSuggestedTarget()
        }
    }
}

private struct ControlRow: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Menu {
                    ForEach(TranslationLanguage.allCases) { language in
                        Button {
                            model.translation.selectTarget(language)
                        } label: {
                            if language == model.translation.targetLanguage {
                                Label(language.displayName, systemImage: "checkmark")
                            } else {
                                Text(language.displayName)
                            }
                        }
                    }
                } label: {
                    Label(
                        "翻訳先: \(model.translation.targetLanguage.displayName)",
                        systemImage: "globe"
                    )
                    .font(.subheadline)
                }
                .accessibilityIdentifier("translate.targetMenu")

                Spacer()

                Button {
                    Task { await model.translate() }
                } label: {
                    if model.translation.isTranslating {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 72)
                    } else {
                        Label("翻訳", systemImage: "character.bubble.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.translation.canTranslate || model.engineState != .ready)
                .accessibilityIdentifier("translate.run")
            }

            if model.translation.targetLanguage == .japanese {
                Toggle(isOn: Binding(
                    get: { model.translation.form == .plain },
                    set: { model.translation.form = $0 ? .plain : .polite }
                )) {
                    Text("常体で出力").font(.subheadline)
                }
                .accessibilityIdentifier("translate.plainForm")
            }
        }
        .cardStyle()
    }
}

private struct OutputSection: View {
    @Bindable var model: AppModel

    private var hasOutput: Bool {
        !model.translation.output.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("訳文")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if hasOutput {
                    Button {
                        UIPasteboard.general.string = model.translation.output
                    } label: {
                        Label("コピー", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .accessibilityIdentifier("translate.copy")
                }
            }

            Text(hasOutput ? model.translation.output : "ここに訳文が表示されます")
                .font(.body)
                .foregroundStyle(hasOutput ? .primary : .secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("translate.output")

            if let error = model.translation.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("translate.error")
            }
        }
        .cardStyle()
    }
}

private struct AttributionFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Built with PLaMo")
                .font(.caption2.weight(.semibold))
            Link("PLaMo Community License", destination: ModelCatalog.licenseURL)
                .font(.caption2)
            Text("モデルの重みはアプリに同梱していません。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
}

private extension View {
    func cardStyle() -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
