import SwiftUI

/// First launch: where is Houston? (the Apollo's address at home, or its Tailscale name).
struct SetupView: View {
    @EnvironmentObject var store: Store
    @State private var address = ""
    @State private var message = ""
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 40)).foregroundStyle(.orange).padding(.top, 30)
                Text("Connect to your Apollo").font(.largeTitle.bold())
                Text("Houston runs on your Apollo. Enter its address: the IP from your router (like 192.168.1.50), or its Tailscale name to use the app away from home.")
                    .foregroundStyle(.secondary)
                TextField("192.168.1.50", text: $address)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .padding(14).background(RoundedRectangle(cornerRadius: 10).strokeBorder(.secondary.opacity(0.4)))
                    .onSubmit { Task { await connect() } }
                Button { Task { await connect() } } label: {
                    Text(busy ? "Looking for Houston…" : "Connect").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).tint(.primary).disabled(busy)
                if !message.isEmpty { Text(message).font(.callout).foregroundStyle(.secondary) }
                Text("Houston must be installed on the Apollo first. Away from home, turn on Tailscale on this phone.")
                    .font(.footnote).foregroundStyle(.tertiary)
            }
            .padding(22)
        }
        .onAppear { if let b = store.base { address = b.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: ":8088", with: "") } }
    }

    private func connect() async {
        guard let base = HoustonAddress.normalize(address) else { message = "Enter your Apollo's address."; return }
        busy = true
        defer { busy = false }
        do {
            let v = try await HoustonAPI(base: base).check()
            message = "Found Houston \(v)."
            if base != store.base { store.key = nil; store.askedForKey = false }
            store.base = base
        } catch {
            message = "Couldn't reach Houston at \(base). \(error.localizedDescription) Check the address, that this phone is on your home Wi-Fi (or Tailscale), and that Houston is installed."
        }
    }
}
