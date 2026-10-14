import SwiftUI

struct OpenAISettingsView: View {
    @State private var keyInput = ""
    @State private var isConfigured = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        Form {
            Section("Create an API key") {
                Text("Open your OpenAI API dashboard and choose the project you want this app to use.")
                Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                    Label("Create an OpenAI API key", systemImage: "arrow.up.right.square")
                }
                Text("Choose Create new secret key and copy it before leaving the page. OpenAI shows the full key only when it is created. Return here, paste it below, and save.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Credential", value: isConfigured ? "Configured on this device" : "Not configured")
                SecureField("OpenAI API key", text: $keyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                Button(isConfigured ? "Replace API Key" : "Save API Key", action: saveKey)
                    .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if isConfigured {
                    Button("Remove API Key", role: .destructive, action: removeKey)
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(isError ? .red : .secondary)
                }
            } header: {
                Text("OpenAI API")
            } footer: {
                Text("The key is stored in this device’s Keychain and is used only when you explicitly analyze a meal. Saving a key does not contact OpenAI. The ChatGPT subscription is separate from API billing.")
            }

            Section("Privacy and billing") {
                Text("This personal app sends the meal description you enter, any photo you add, and fixed meal-estimation instructions directly to OpenAI. You can analyze from a description alone, a photo alone, or both. It does not send your diary or HealthKit history. Photo metadata is removed before upload. OpenAI processes API inputs under its current data controls; store=false does not promise zero provider retention.")
                Link("OpenAI API usage and billing", destination: URL(string: "https://platform.openai.com/settings/organization/billing/overview")!)
                Link("OpenAI API data controls", destination: URL(string: "https://developers.openai.com/api/docs/guides/your-data")!)
                Text("A key stored in a client app is not a server secret. This direct personal setup is for private deployment. A shared or distributed app needs an authenticated backend that owns the key and limits use.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("OpenAI API")
        .analyticsScreen("openai_settings")
        .task { refreshConfiguredState() }
    }

    private func refreshConfiguredState() {
        do { isConfigured = try OpenAICredentialStore.shared.load() != nil }
        catch { isConfigured = false; message = error.localizedDescription; isError = true }
    }

    private func saveKey() {
        let value = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        do {
            try OpenAICredentialStore.shared.save(value)
            keyInput = ""
            isConfigured = true
            message = "API key saved securely. No request was sent."
            isError = false
        } catch { message = error.localizedDescription; isError = true }
    }

    private func removeKey() {
        do {
            try OpenAICredentialStore.shared.delete()
            keyInput = ""
            isConfigured = false
            message = "API key removed from this device."
            isError = false
        } catch { message = error.localizedDescription; isError = true }
    }
}
