import KotobaCore
import SwiftUI

struct SettingsView: View {
    let status: ServerStatus

    @Environment(\.dismiss) private var dismiss
    @AppStorage(StorageKey.serverURL) private var serverURL = ""
    @AppStorage(StorageKey.form) private var form = ""
    @State private var url = ""
    @State private var apiKey = ""
    @State private var errorMessage: String?
    @State private var isChecking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("サーバー URL", text: $url, prompt: Text(verbatim: "https://server.example"))
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("serverURL")
                        StatusDot(status: status)
                    }
                    SecureField("API キー", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("apiKey")
                } footer: {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("settingsError")
                    }
                }

                Picker("日本語の文体", selection: $form) {
                    Text("自動").tag("")
                    Text("です・ます").tag(OutputForm.polite.rawValue)
                    Text("だ・である").tag(OutputForm.plain.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isChecking {
                        ProgressView()
                    } else {
                        Button("保存") { Task { await save() } }
                            .disabled(url.isEmpty)
                            .accessibilityIdentifier("saveButton")
                    }
                }
            }
            .onAppear {
                url = serverURL
                apiKey = Keychain.apiKey
            }
        }
    }

    private func save() async {
        isChecking = true
        defer { isChecking = false }
        errorMessage = nil
        serverURL = url
        Keychain.apiKey = apiKey

        if let error = await TranslationClient(serverURL: url, apiKey: apiKey).status().error {
            errorMessage = error.localizedDescription
        } else {
            dismiss()
        }
    }
}
