import AppIntents

/// Siri and Shortcuts: "Hey Siri, Houston status", "Switch Houston to Whisper", start and stop.
enum HoustonMode: String, AppEnum {
    case whisper, eco, balanced, turbo, super_eco

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Power mode"
    static var caseDisplayRepresentations: [HoustonMode: DisplayRepresentation] = [
        .whisper: "Whisper", .eco: "Eco", .balanced: "Balanced", .turbo: "Turbo", .super_eco: "Super Eco",
    ]
}

private func api() throws -> HoustonAPI {
    guard let a = Store.shared.api else { throw HoustonError(message: "Open Houston and connect it to your Apollo first.") }
    return a
}

struct StatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Apollo status"
    static var description = IntentDescription("Hear how your Apollo is doing.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = try await api().say()
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct ModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set power mode"
    static var description = IntentDescription("Switch your Apollo's power mode. A running miner restarts to apply it.")

    @Parameter(title: "Mode") var mode: HoustonMode

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = try await api().action(mode.rawValue)
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct StartIntent: AppIntent {
    static var title: LocalizedStringResource = "Start mining"
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: try await api().action("start")))
    }
}

struct StopIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop mining"
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: try await api().action("stop")))
    }
}

struct HoustonShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StatusIntent(), phrases: ["\(.applicationName) status", "How is my Apollo in \(.applicationName)"],
                    shortTitle: "Apollo status", systemImageName: "gauge.with.dots.needle.33percent")
        AppShortcut(intent: ModeIntent(), phrases: ["Switch \(.applicationName) to \(\.$mode)", "\(.applicationName) \(\.$mode)"],
                    shortTitle: "Power mode", systemImageName: "dial.medium")
        AppShortcut(intent: StartIntent(), phrases: ["Start mining with \(.applicationName)"], shortTitle: "Start mining", systemImageName: "play.fill")
        AppShortcut(intent: StopIntent(), phrases: ["Stop mining with \(.applicationName)"], shortTitle: "Stop mining", systemImageName: "stop.fill")
    }
}
