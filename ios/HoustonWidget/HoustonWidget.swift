import AppIntents
import SwiftUI
import WidgetKit

/// Widget settings: where Houston is (long-press the widget › Edit Widget).
struct HoustonWidgetConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Houston"
    static var description = IntentDescription("Your Apollo and the bitcoin price.")

    @Parameter(title: "Apollo address", default: "") var address: String
}

struct HoustonEntry: TimelineEntry {
    let date: Date
    let status: HoustonStatus?
    let note: String?
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HoustonEntry { HoustonEntry(date: .now, status: .sample, note: nil) }

    func snapshot(for config: HoustonWidgetConfig, in context: Context) async -> HoustonEntry {
        if context.isPreview { return HoustonEntry(date: .now, status: .sample, note: nil) }
        return await load(config)
    }

    func timeline(for config: HoustonWidgetConfig, in context: Context) async -> Timeline<HoustonEntry> {
        let entry = await load(config)
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60)))
    }

    private func load(_ config: HoustonWidgetConfig) async -> HoustonEntry {
        guard let base = HoustonAddress.normalize(config.address) else {
            return HoustonEntry(date: .now, status: nil, note: "Long-press › Edit Widget to enter your Apollo's address")
        }
        do {
            return HoustonEntry(date: .now, status: try await HoustonAPI(base: base).status(), note: nil)
        } catch {
            return HoustonEntry(date: .now, status: nil, note: "Can't reach Houston (home Wi-Fi or Tailscale?)")
        }
    }
}

struct HoustonWidgetView: View {
    var entry: HoustonEntry
    @Environment(\.widgetFamily) var family

    private let btc = Color(red: 0.97, green: 0.58, blue: 0.10)

    var body: some View {
        if let s = entry.status {
            VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(s.priceText).font(.system(size: family == .systemSmall ? 20 : 26, weight: .bold)).foregroundStyle(btc)
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Spacer(minLength: 4)
                    if family != .systemSmall { Text(s.changeText).font(.caption.monospaced()).foregroundStyle((s.change ?? 0) >= 0 ? Color.green : Color.red) }
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle().fill(color(s.state)).frame(width: 9, height: 9)
                    Text(s.hashText).font(.system(size: family == .systemSmall ? 26 : 32, weight: .bold)).minimumScaleFactor(0.6).lineLimit(1)
                    Text("TH/s").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if family != .systemSmall { Text(HoustonStatus.modeName(s.mode)).font(.subheadline) }
                }
                Text(family == .systemSmall ? HoustonStatus.modeName(s.mode).isEmpty ? s.stateText : HoustonStatus.modeName(s.mode)
                     : "\(s.stateText)\(s.watts.map { " · \(Int($0)) W" } ?? "") · \(s.time.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Houston").font(.headline)
                Text(entry.note ?? "").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func color(_ state: String?) -> Color {
        switch state {
        case "online": return .green
        case "pending": return .yellow
        case nil: return .gray
        default: return .red
        }
    }
}

struct HoustonWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "HoustonWidget", intent: HoustonWidgetConfig.self, provider: Provider()) { entry in
            HoustonWidgetView(entry: entry)
                .containerBackground(Color(red: 0.08, green: 0.086, blue: 0.07), for: .widget)
                .environment(\.colorScheme, .dark)
        }
        .configurationDisplayName("Houston")
        .description("Your Apollo's status and the bitcoin price.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct HoustonWidgets: WidgetBundle {
    var body: some Widget { HoustonWidget() }
}
