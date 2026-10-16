import SwiftUI

/// App settings, private to this app.
final class Store: ObservableObject {
    static let shared = Store()
    private let d = UserDefaults.standard

    @Published var base: String? { didSet { d.set(base, forKey: "base") } }
    @Published var key: String? { didSet { d.set(key, forKey: "key") } }
    var askedForKey: Bool { get { d.bool(forKey: "askedKey") } set { d.set(newValue, forKey: "askedKey") } }

    init() {
        base = d.string(forKey: "base")
        key = d.string(forKey: "key")
    }

    var api: HoustonAPI? { base.map { HoustonAPI(base: $0, key: key) } }
}

@main
struct HoustonApp: App {
    @StateObject private var store = Store.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if store.base == nil { SetupView() } else { HoustonScreen() }
            }
            .environmentObject(store)
            .preferredColorScheme(nil)
        }
    }
}
