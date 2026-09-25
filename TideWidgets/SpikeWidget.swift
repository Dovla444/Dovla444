import AppIntents
import SwiftUI
import SyncKit
import WidgetKit

struct SpikeEntry: TimelineEntry {
    let date: Date
    let lastEvent: SpikeEvent?
}

struct SpikeProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpikeEntry {
        SpikeEntry(date: .now, lastEvent: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SpikeEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpikeEntry>) -> Void) {
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> SpikeEntry {
        let lastEvent = try? SpikeActions.fromMainBundle().log.recent(limit: 1).last
        return SpikeEntry(date: .now, lastEvent: lastEvent)
    }
}

/// Phase 0 widget: shows the last spike event and runs intents from its buttons,
/// to find out which process executes them and whether they can reach the vault and the Keychain.
struct SpikeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpikeWidget", provider: SpikeProvider()) { entry in
            SpikeWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tide Spike")
        .description("Runs Phase 0 experiments.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

struct SpikeWidgetView: View {
    let entry: SpikeEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryCircular {
            // Lock Screen: tests whether an intent can reach the vault while the device is locked.
            Button(intent: AppendTestLineIntent(trigger: "lock screen widget")) {
                Image(systemName: "text.append").font(.title2)
            }
        } else {
            homeScreenBody
        }
    }

    private var homeScreenBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let event = entry.lastEvent {
                Text(event.action).font(.caption.bold()).lineLimit(1)
                Text(event.outcome).font(.caption2).lineLimit(3)
                Text(event.process).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Text(event.date, style: .relative).font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("No spike events yet").font(.caption)
            }
            Spacer(minLength: 0)
            HStack {
                Button(intent: AppendTestLineIntent(trigger: "widget")) {
                    Image(systemName: "text.append")
                }
                Button(intent: SpikeFetchIntent(trigger: "widget")) {
                    Image(systemName: "arrow.down.circle")
                }
            }
            .font(.title3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
