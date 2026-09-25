import AppIntents
import SyncKit

// Compiled into both the app and the widget extension. Each result is logged together with the
// bundle identifier of the process that ran it, which answers where widget intents execute.

struct AppendTestLineIntent: AppIntent {
    static let title: LocalizedStringResource = "Append Test Line"
    static let description = IntentDescription("Spike: appends a line to Tide-Spike.md in the vault.")
    static let openAppWhenRun = false

    @Parameter(title: "Trigger", default: "shortcut")
    var trigger: String

    init() {}

    init(trigger: String) {
        self.trigger = trigger
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let actions = try SpikeActions.fromMainBundle()
        let trigger = self.trigger
        let event = await Task.detached { actions.appendTestLine(trigger: trigger) }.value
        return .result(dialog: "\(event.outcome)")
    }
}

struct SpikeFetchIntent: AppIntent {
    static let title: LocalizedStringResource = "Fetch Vault"
    static let description = IntentDescription("Spike: fetches from GitHub with libgit2 in the current process.")
    static let openAppWhenRun = false

    @Parameter(title: "Trigger", default: "shortcut")
    var trigger: String

    init() {}

    init(trigger: String) {
        self.trigger = trigger
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let actions = try SpikeActions.fromMainBundle()
        let trigger = self.trigger
        let event = await Task.detached { actions.fetch(trigger: trigger) }.value
        return .result(dialog: "\(event.outcome)")
    }
}

struct MeasureRuntimeIntent: AppIntent {
    static let title: LocalizedStringResource = "Measure Runtime"
    static let description = IntentDescription(
        "Spike: writes a heartbeat every second to measure how long an intent may run before iOS stops it."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Maximum seconds", default: 600)
    var maxSeconds: Int

    @Parameter(title: "Trigger", default: "shortcut")
    var trigger: String

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let actions = try SpikeActions.fromMainBundle()
        let probe = await actions.measureRuntime(trigger: trigger, maxSeconds: maxSeconds)
        return .result(dialog: "Ran \(Int(probe.seconds)) s, \(probe.ending ?? "?")")
    }
}
