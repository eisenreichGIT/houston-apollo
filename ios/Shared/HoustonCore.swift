import Foundation

/// Houston's address: "192.168.1.50" -> "http://192.168.1.50:8088"; https://name (Houston's https address) is kept.
enum HoustonAddress {
    static func normalize(_ input: String) -> String? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if s.isEmpty { return nil }
        if !s.hasPrefix("http://") && !s.hasPrefix("https://") { s = "http://" + s }
        guard let range = s.range(of: "://") else { return nil }
        let scheme = String(s[..<range.lowerBound])
        var rest = String(s[range.upperBound...])
        if let slash = rest.firstIndex(of: "/") { rest = String(rest[..<slash]) }
        let hasPort = rest.hasPrefix("[") ? rest.contains("]:") : rest.contains(":")
        if !hasPort && scheme == "http" { rest += ":8088" }
        return scheme + "://" + rest
    }
}

/// What the widget and Siri show, from Houston's /api/glance (public) and /api/price (public).
struct HoustonStatus: Codable, Equatable {
    var state: String?
    var ths: Double?
    var watts: Double?
    var mode: String?
    var chassis: String?
    var price: Double?
    var fiat: String = "USD"
    var change: Double?
    var time: Date = .now

    static let sample = HoustonStatus(state: "online", ths: 5.75, watts: 209, mode: "eco", chassis: nil, price: 98765, fiat: "USD", change: 1.24)

    var stateText: String {
        switch state {
        case "online": return "Mining"
        case "offline": return "Stopped"
        case "pending": return "Starting"
        case "unreachable": return "Can't reach the Apollo"
        case nil: return "Waiting for Houston"
        default: return state ?? ""
        }
    }

    var hashText: String {
        if state == "online", let t = ths { return String(format: "%.2f", t) }
        return state == "offline" ? "0.00" : "–"
    }

    var priceText: String {
        guard let p = price else { return "₿ –" }
        return p.formatted(.currency(code: fiat).precision(.fractionLength(0)))
    }

    var changeText: String {
        guard let c = change else { return "" }
        return (c >= 0 ? "▲ +" : "▼ −") + String(format: "%.2f%%", abs(c))
    }

    static func modeName(_ m: String?) -> String {
        guard let m else { return "" }
        if m.hasPrefix("custom:") { return String(m.dropFirst(7)) + " TH/s" }
        switch m {
        case "super_eco": return "Super Eco"
        case "whisper": return "Whisper"
        case "custom": return "Custom"
        default: return m.capitalized
        }
    }
}

struct HoustonError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Talks to Houston on the Apollo.
struct HoustonAPI {
    let base: String
    var key: String? = nil

    private func request(_ path: String, method: String = "GET", bearer: String? = nil, body: Data? = nil) -> URLRequest? {
        guard let url = URL(string: base + path) else { return nil }
        var r = URLRequest(url: url, timeoutInterval: method == "POST" ? 30 : 8)
        r.httpMethod = method
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("HoustonApp/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        if let bearer { r.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization") }
        if method == "POST" {
            r.httpBody = body ?? Data("{}".utf8)
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    func call(_ path: String, method: String = "GET", bearer: String? = nil) async throws -> (Int, Data) {
        guard let req = request(path, method: method, bearer: bearer) else { throw HoustonError(message: "That address doesn't look right.") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        return ((resp as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    func json(_ path: String, bearer: String? = nil) async throws -> [String: Any] {
        let (code, data) = try await call(path, bearer: bearer)
        guard (200..<300).contains(code) else { throw HoustonError(message: "Houston answered \(code).") }
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// Is there a Houston at this address? Returns its version.
    func check() async throws -> String {
        let j = try await json("/api/device")
        guard let v = j["version"] as? String else { throw HoustonError(message: "That address answers, but it isn't Houston.") }
        return v
    }

    func status() async throws -> HoustonStatus {
        let g = try await json("/api/glance")
        var s = HoustonStatus()
        s.state = g["status"] as? String
        if let h = g["ghs"] as? Double { s.ths = h / 1000 }
        s.watts = g["watts"] as? Double
        s.mode = g["mode"] as? String
        s.chassis = g["chassis"] as? String
        if let p = try? await json("/api/price?range=1D&points=0"), (p["enabled"] as? Bool) == true {
            s.price = p["price"] as? Double
            s.fiat = p["fiat"] as? String ?? "USD"
            s.change = (p["change"] as? Double) ?? (p["change24"] as? Double)
        }
        s.time = .now
        return s
    }

    /// Houston's spoken status (needs the shortcut key).
    func say() async throws -> String {
        guard let key else { throw HoustonError(message: "Open Houston and turn on Siri in the app's settings first.") }
        let (code, data) = try await call("/api/v1/say", bearer: key)
        if code == 401 { throw HoustonError(message: "Houston's shortcut key changed. Open the app to pair again.") }
        return String(decoding: data, as: UTF8.self)
    }

    func action(_ name: String) async throws -> String {
        guard let key else { throw HoustonError(message: "Open Houston and turn on Siri in the app's settings first.") }
        let (code, data) = try await call("/api/v1/action/" + name, method: "POST", bearer: key)
        if code == 401 { throw HoustonError(message: "Houston's shortcut key changed. Open the app to pair again.") }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Gets (or makes) Houston's shortcut key with the sign-in from the Houston page.
    func pair(token: String) async throws -> String {
        let (code, data) = try await call("/api/automation", bearer: token)
        if code == 401 { throw HoustonError(message: "Please sign in to Houston again.") }
        if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let k = j["key"] as? String { return k }
        let (_, made) = try await call("/api/automation", method: "POST", bearer: token)
        if let j = try? JSONSerialization.jsonObject(with: made) as? [String: Any], let k = j["key"] as? String { return k }
        throw HoustonError(message: "Houston didn't give a key.")
    }
}
