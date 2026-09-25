import AppIntents

/// Makes the spike intents available in Shortcuts, so they can run from personal automations
/// ("When Obsidian is opened/closed") with the device unlocked and locked.
struct SpikeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AppendTestLineIntent(),
            phrases: ["Append test line in \(.applicationName)"],
            shortTitle: "Append Test Line",
            systemImageName: "text.append"
        )
        AppShortcut(
            intent: SpikeFetchIntent(),
            phrases: ["Fetch vault in \(.applicationName)"],
            shortTitle: "Fetch Vault",
            systemImageName: "arrow.down.circle"
        )
        AppShortcut(
            intent: MeasureRuntimeIntent(),
            phrases: ["Measure runtime in \(.applicationName)"],
            shortTitle: "Measure Runtime",
            systemImageName: "stopwatch"
        )
    }
}
