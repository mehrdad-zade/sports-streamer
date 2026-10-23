import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var draftURL = ""
    @State private var testResult: String?
    @State private var isTesting = false

    private var normalizedDraft: URL? { AppSettings.normalize(draftURL) }

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com", text: $draftURL)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button {
                        Task { await test() }
                    } label: {
                        HStack {
                            Text("Test site")
                            if isTesting { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(normalizedDraft == nil || isTesting)
                    if let testResult { Text(testResult).font(.footnote).foregroundStyle(.secondary) }
                } header: {
                    Text("Streaming site")
                } footer: {
                    Text("The app reads this page and its sport category pages to build the event list.")
                }

                Section("While watching") {
                    Picker("Re-check sources every", selection: $settings.recheckInterval) {
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                        Text("2 minutes").tag(120)
                        Text("5 minutes").tag(300)
                    }
                    Toggle("Auto-switch when a stream stops", isOn: $settings.autoSwitch)
                }

                Section {
                    Button("Reset to default site") { draftURL = AppSettings.defaultSiteURL }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let url = normalizedDraft { settings.siteURL = url.absoluteString }
                        dismiss()
                    }
                    .disabled(normalizedDraft == nil)
                }
            }
            .onAppear { draftURL = settings.siteURL }
        }
    }

    private func test() async {
        guard let url = normalizedDraft else { return }
        isTesting = true
        defer { isTesting = false }
        do {
            let page = try await HTMLFetcher.fetch(url)
            let events = EventListParser.parse(html: page.html, pageURL: page.finalURL)
            let categories = EventListParser.categoryLinks(html: page.html, pageURL: page.finalURL)
            testResult = "Found \(events.count) events on the homepage and \(categories.count) category pages."
        } catch {
            testResult = "Couldn't load: \(error.localizedDescription)"
        }
    }
}
