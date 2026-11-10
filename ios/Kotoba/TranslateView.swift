import KotobaCore
import SwiftUI

struct TranslateView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage(StorageKey.serverURL) private var serverURL = ""
    @AppStorage(StorageKey.target) private var target = "ja"
    @AppStorage(StorageKey.form) private var form = ""
    @State private var model = TranslationModel()
    @State private var status = ServerStatus.unreachable
    @State private var showingSettings = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 16) {
                        inputPane
                        outputPane
                    }
                } else {
                    VStack(spacing: 12) {
                        inputPane
                        outputPane
                    }
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { targetPicker }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    StatusDot(status: shownStatus)
                    Button("設定", systemImage: "gearshape") { showingSettings = true }
                        .accessibilityIdentifier("settingsButton")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingSettings) { SettingsView(status: shownStatus) }
            .onAppear {
                if serverURL.isEmpty { showingSettings = true }
            }
            .task(id: serverURL) { await pollStatus() }
        }
    }

    /// A request to a sleeping server loads the weights first.
    private var shownStatus: ServerStatus {
        model.isTranslating && status == .sleeping ? .loading : status
    }

    private var client: TranslationClient {
        TranslationClient(serverURL: serverURL, apiKey: Keychain.apiKey)
    }

    private func pollStatus() async {
        while !Task.isCancelled {
            status = await client.status()
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private var targetPicker: some View {
        Picker("翻訳先の言語", selection: $target) {
            Text("日本語 ⇄ 英語").tag(Languages.auto)
            ForEach(Languages.codes, id: \.self) { code in
                Text(Languages.displayName(for: code)).tag(code)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .accessibilityIdentifier("targetPicker")
    }

    private var inputPane: some View {
        VStack(spacing: 12) {
            TextEditor(text: $model.input)
                .focused($inputFocused)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                .accessibilityLabel("原文")
                .accessibilityIdentifier("sourceText")

            Group {
                if model.isTranslating {
                    Button("停止", systemImage: "stop.fill") { model.cancel() }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("stopButton")
                } else {
                    Button("翻訳") { translate() }
                        .disabled(!model.canTranslate)
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityIdentifier("translateButton")
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var outputPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let error = model.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("errorMessage")
                }
                if !model.output.isEmpty {
                    Text(model.output)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("translatedText")
                }
                if model.isTranslating {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .bottomTrailing) {
            if !model.output.isEmpty, !model.isTranslating {
                HStack(spacing: 16) {
                    Button("コピー", systemImage: "doc.on.doc") { UIPasteboard.general.string = model.output }
                    ShareLink(item: model.output) { Label("共有", systemImage: "square.and.arrow.up") }
                }
                .labelStyle(.iconOnly)
                .padding(10)
                .background(.regularMaterial, in: .capsule)
            }
        }
    }

    private func translate() {
        inputFocused = false
        model.translate(using: client, target: target, form: OutputForm(rawValue: form))
    }
}
