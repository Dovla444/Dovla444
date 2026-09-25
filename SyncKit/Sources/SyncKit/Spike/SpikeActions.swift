import Foundation

public enum SpikeError: Error, CustomStringConvertible {
    case noToken
    case noRepository
    case notCloned

    public var description: String {
        switch self {
        case .noToken: "No GitHub token saved"
        case .noRepository: "No repository selected"
        case .notCloned: "Clone first"
        }
    }
}

/// How long the last runtime measurement ran before it finished, was cancelled or was killed.
public struct RuntimeProbe: Codable, Sendable {
    public let trigger: String
    public let process: String
    public let started: Date
    public var lastHeartbeat: Date
    /// "completed", "cancelled", or nil if the process was killed before it could say.
    public var ending: String?

    public var seconds: Double { lastHeartbeat.timeIntervalSince(started) }
}

/// Phase 0 experiments, callable from the app, App Intents and the widget. Every action logs
/// the process it ran in and whether the device was locked, so the results answer the spike questions.
///
/// Synchronous methods block; call them off the main actor.
public struct SpikeActions: Sendable {
    public let environment: TideEnvironment
    public let log: SpikeLog
    public let bookmarks: VaultBookmarkStore
    public let tokens: KeychainTokenStore
    public let lockProbe: LockProbe

    public init(environment: TideEnvironment) {
        self.environment = environment
        log = SpikeLog(environment: environment)
        bookmarks = VaultBookmarkStore(environment: environment)
        tokens = KeychainTokenStore(accessGroup: environment.keychainGroup)
        lockProbe = LockProbe(environment: environment)
    }

    public static func fromMainBundle() throws -> SpikeActions {
        SpikeActions(environment: try .fromMainBundle())
    }

    // MARK: Repository selection

    public func selectedRepository() -> GitHubRepository? {
        guard let data = try? Data(contentsOf: environment.repositoryURL) else { return nil }
        return try? JSONDecoder().decode(GitHubRepository.self, from: data)
    }

    public func select(_ repository: GitHubRepository) throws {
        try JSONEncoder().encode(repository).write(to: environment.repositoryURL, options: FileProtection.writingOptions)
    }

    // MARK: Experiments

    /// (a/b/c) Appends a timestamped line to `Tide-Spike.md` in the vault.
    @discardableResult
    public func appendTestLine(trigger: String) -> SpikeEvent {
        run("append line (\(trigger))") {
            try bookmarks.withVaultAccess { vault in
                let line = "- \(Date.now.formatted(.iso8601)) · \(trigger) · \(Bundle.main.bundleIdentifier ?? "?")\n"
                try Self.coordinatedAppend(Data(line.utf8), to: vault.appending(path: "Tide-Spike.md"))
            }
            return "ok"
        }
    }

    /// Creates the git directory in the container (replacing a previous spike clone), fetches the selected
    /// repository and writes its files into the vault without overwriting anything that is already there.
    @discardableResult
    public func cloneIntoContainer(trigger: String) -> SpikeEvent {
        run("clone (\(trigger))") {
            guard let token = try tokens.token() else { throw SpikeError.noToken }
            guard let repository = selectedRepository() else { throw SpikeError.noRepository }
            return try bookmarks.withVaultAccess { vault in
                // Only the git directory in the app container is removed, never anything in the vault.
                try? FileManager.default.removeItem(at: environment.gitDirectoryURL)
                let git = try GitRepository(gitDirectory: environment.gitDirectoryURL, workDirectory: vault)
                try git.setOrigin(repository.cloneURL)
                let fetchStart = Date.now
                let stats = try git.fetchOrigin(token: token)
                let fetchSeconds = Date.now.timeIntervalSince(fetchStart)
                let skipped = try git.checkoutRemoteBranch(repository.defaultBranch)
                let files = Self.fileCount(in: vault)
                return "ok · \(stats.objects) objects, \(ByteCountFormatter.string(fromByteCount: Int64(stats.bytes), countStyle: .file)), "
                    + "fetch \(fetchSeconds.formatted(.number.precision(.fractionLength(1)))) s, "
                    + "\(files) files in vault, \(skipped.count) existing files left untouched"
            }
        }
    }

    /// Fetches from GitHub into the existing git directory (no changes to the vault).
    @discardableResult
    public func fetch(trigger: String) -> SpikeEvent {
        run("fetch (\(trigger))") {
            guard let token = try tokens.token() else { throw SpikeError.noToken }
            guard FileManager.default.fileExists(atPath: environment.gitDirectoryURL.path(percentEncoded: false)) else {
                throw SpikeError.notCloned
            }
            return try bookmarks.withVaultAccess { vault in
                let git = try GitRepository(gitDirectory: environment.gitDirectoryURL, workDirectory: vault)
                let stats = try git.fetchOrigin(token: token)
                return "ok · \(stats.objects) new objects"
            }
        }
    }

    /// Writes a heartbeat every second until `maxSeconds` pass or the task is cancelled.
    /// If iOS kills the process, the last heartbeat shows how long it lived.
    public func measureRuntime(trigger: String, maxSeconds: Int) async -> RuntimeProbe {
        let process = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        var probe = RuntimeProbe(trigger: trigger, process: process, started: .now, lastHeartbeat: .now, ending: nil)
        let deviceLocked = lockProbe.isDeviceLocked()
        for _ in 0..<max(maxSeconds, 1) {
            probe.lastHeartbeat = .now
            write(probe)
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                probe.ending = "cancelled"
                break
            }
        }
        probe.lastHeartbeat = .now
        if probe.ending == nil { probe.ending = "completed" }
        write(probe)
        log.append(SpikeEvent(
            action: "runtime (\(trigger))",
            deviceLocked: deviceLocked,
            outcome: probe.ending ?? "?",
            seconds: probe.seconds
        ))
        return probe
    }

    public func lastRuntimeProbe() -> RuntimeProbe? {
        guard let data = try? Data(contentsOf: environment.runtimeProbeURL) else { return nil }
        return try? JSONDecoder.spike.decode(RuntimeProbe.self, from: data)
    }

    // MARK: Helpers

    private func write(_ probe: RuntimeProbe) {
        try? JSONEncoder.spike.encode(probe).write(to: environment.runtimeProbeURL, options: FileProtection.writingOptions)
    }

    private func run(_ action: String, _ body: () throws -> String) -> SpikeEvent {
        let deviceLocked = lockProbe.isDeviceLocked()
        let start = Date.now
        let outcome: String
        do {
            outcome = try body()
        } catch {
            outcome = "error: \(error)"
        }
        let event = SpikeEvent(
            action: action,
            deviceLocked: deviceLocked,
            outcome: outcome,
            seconds: Date.now.timeIntervalSince(start)
        )
        log.append(event)
        return event
    }

    private static func coordinatedAppend(_ data: Data, to file: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: file, options: [], error: &coordinationError) { url in
            do {
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } else {
                    try data.write(to: url)
                }
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    static func fileCount(in folder: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return 0
        }
        var count = 0
        for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            count += 1
        }
        return count
    }
}
