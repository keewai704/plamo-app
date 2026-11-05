import SwiftUI
import UniformTypeIdentifiers
import PLaMoKit

struct ModelListView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var isImporting = false

    private var ggufType: UTType {
        UTType(filenameExtension: "gguf") ?? .data
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(appModel.modelVariants) { variant in
                        modelRow(variant)
                    }
                } header: {
                    Text("モデル")
                } footer: {
                    Text("Q3_K_M が推奨です。Q2_K はさらに小さい代わりに品質が下がります。")
                }

                Section {
                    Button {
                        isImporting = true
                    } label: {
                        Label("GGUF ファイルを読み込む", systemImage: "doc.badge.plus")
                    }
                    .accessibilityIdentifier("model.import")
                } footer: {
                    Text("Files などから plamo-3-translate-0.8b の GGUF を選択します。読み込んだファイルは推奨モデルとして保存されます。")
                }

                Section("ライセンス") {
                    Text("Built with PLaMo")
                    Link("PLaMo Community License", destination: ModelCatalog.licenseURL)
                    Link("モデルカード", destination: ModelCatalog.modelPageURL)
                    Text("モデルは再配布せず、各端末で取得します。生成物を公開する場合は「PLaMo の出力である」旨の表示が必要です。")
                        .font(.footnote)
                }

                if !LlamaEngine.isSupported {
                    Section {
                        Label("この環境（シミュレータ）では llama.cpp を読み込めないため、モックで動作します。実機で確認してください。", systemImage: "testtube.2")
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("モデル")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [ggufType]) { result in
                switch result {
                case let .success(url):
                    appModel.importModel(from: url)
                case let .failure(error):
                    appModel.errorMessage = error.localizedDescription
                }
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ variant: ModelVariant) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(variant.displayName)
                        .font(.subheadline.weight(.medium))
                    Text("\(variant.quantization) · \(variant.formattedSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if appModel.isInstalled(variant) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("インストール済み")
                        .accessibilityIdentifier("model.installed.\(variant.quantization)")
                } else if appModel.isDownloading(variant) {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("取得") {
                        appModel.download(variant)
                    }
                    .buttonStyle(.bordered)
                    .disabled(appModel.downloadProgress != nil)
                    .accessibilityIdentifier("model.download.\(variant.quantization)")
                }
            }

            if appModel.isDownloading(variant), let progress = appModel.downloadProgress {
                ProgressView(value: progress) {
                    Text("ダウンロード中 \(Int(progress * 100))%")
                        .font(.caption2)
                }
                .accessibilityIdentifier("model.progress")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if appModel.isInstalled(variant) {
                Button("削除", role: .destructive) {
                    appModel.delete(variant)
                }
            }
        }
    }
}
