import SwiftUI

/// The app's own settings: Houston's address and the Siri pairing.
struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Houston address") {
                    Text(store.base ?? "–")
                    Button("Change address") { store.base = nil; dismiss() }
                }
                Section {
                    if store.key != nil {
                        Text("On. Say “Hey Siri, Houston status”, or find Houston's actions in the Shortcuts app.")
                        Button("Turn off", role: .destructive) { store.key = nil }
                    } else {
                        Text("Off. Close this, sign in to Houston, and tap Turn on when asked.")
                        Button("Ask me again") { store.askedForKey = false; dismiss() }
                    }
                } header: { Text("Siri and shortcuts") }
                Section("Widget") {
                    Text("Long-press your home screen › + › Houston. Then long-press the widget › Edit Widget, and enter your Apollo's address (the same as above). Widgets refresh about every 15 minutes.")
                }
                Section("Alerts") {
                    Text("iPhone apps can't check in the background often enough for alerts, so keep using Houston's alerts: the ntfy app, or Houston from the Home Screen with its https address (Houston › Settings › Alerts).")
                }
                Section {
                    Link("How the app works (guide)", destination: URL(string: "https://github.com/eisenreichGIT/houston-apollo/blob/main/docs/apps.md")!)
                    Text("Houston app 1.0.0 · unofficial, not affiliated with FutureBit").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Houston app")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
