import Foundation
import Observation
import SyncKit

/// State for the Phase 0 spike screen. Blocking work (file access, libgit2) runs off the main actor.
@MainActor
@Observable
final class SpikeModel {
    private(set) var actions: SpikeActions?
    private(set) var setupError: String?
    private(set) var folderName: String?
    private(set) var hasToken = false
    private(set) var repositories: [GitHubRepository] = []
    private(set) var busy: String?
    private(set) var message: String?
    private(set) var events: [SpikeEvent] = []
    private(set) var runtimeProbe: RuntimeProbe?
    var tokenInput = ""
    private(set) var selectedRepository: GitHubRepository?

    init() {
        do {
            actions = try SpikeActions.fromMainBundle()
        } catch {
            setupError = "\(error)"
        }
        refresh()
    }

    func refresh() {
        guard let actions else { return }
        actions.lockProbe.install()
        folderName = try? actions.bookmarks.withVaultAccess { $0.lastPathComponent }
        hasToken = (try? actions.tokens.token()) != nil
        if let repository = actions.selectedRepository() {
            if !repositories.contains(repository) { repositories.append(repository) }
            selectedRepository = repository
        }
        events = actions.log.recent().reversed()
        runtimeProbe = actions.lastRuntimeProbe()
    }

    func select(_ repository: GitHubRepository?) {
        guard let repository, let actions else { return }
        do {
            try actions.select(repository)
            selectedRepository = repository
        } catch {
            message = "\(error)"
        }
    }

    func folderPicked(_ result: Result<URL, Error>) {
        guard let actions else { return }
        do {
            try actions.bookmarks.save(pickedURL: result.get())
        } catch {
            message = "\(error)"
        }
        refresh()
    }

    func saveToken() async {
        guard let actions else { return }
        let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        busy = "Checking token…"
        defer { busy = nil }
        do {
            let found = try await GitHubClient(token: token).accessibleRepositories()
            try actions.tokens.save(token)
            tokenInput = ""
            repositories = found
            message = "Token works. \(found.count) repositories accessible."
            if selectedRepository == nil, let first = found.first { select(first) }
        } catch {
            message = "\(error)"
        }
        refresh()
    }

    func loadRepositories() async {
        guard let actions, let token = try? actions.tokens.token() else { return }
        do {
            repositories = try await GitHubClient(token: token).accessibleRepositories()
        } catch {
            message = "\(error)"
        }
    }

    func appendLine() async {
        await perform("Writing…") { $0.appendTestLine(trigger: "app") }
    }

    func clone() async {
        await perform("Cloning…") { $0.cloneIntoContainer(trigger: "app") }
    }

    func fetch() async {
        await perform("Fetching…") { $0.fetch(trigger: "app") }
    }

    func clearLog() {
        actions?.log.clear()
        refresh()
    }

    private func perform(_ label: String, _ work: @escaping @Sendable (SpikeActions) -> SpikeEvent) async {
        guard let actions else { return }
        busy = label
        let event = await Task.detached { work(actions) }.value
        busy = nil
        message = "\(event.outcome) (\(event.seconds?.formatted(.number.precision(.fractionLength(2))) ?? "?") s)"
        refresh()
    }
}
