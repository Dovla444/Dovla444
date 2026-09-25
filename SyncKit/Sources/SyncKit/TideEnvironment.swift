import Foundation

public enum TideEnvironmentError: Error, CustomStringConvertible {
    case missingInfoPlistKeys
    case appGroupUnavailable(String)

    public var description: String {
        switch self {
        case .missingInfoPlistKeys: "TideAppGroup / TideKeychainGroup missing from Info.plist"
        case .appGroupUnavailable(let id): "App Group \(id) is not available (check entitlements)"
        }
    }
}

/// Identifiers and locations shared by the app, the widget extension and App Intents.
public struct TideEnvironment: Sendable {
    public let appGroupID: String
    public let keychainGroup: String
    /// `Library/Application Support/Tide` inside the App Group container.
    public let containerURL: URL

    public init(appGroupID: String, keychainGroup: String, containerURL: URL) {
        self.appGroupID = appGroupID
        self.keychainGroup = keychainGroup
        self.containerURL = containerURL
    }

    /// Reads the identifiers that Config/Tide.xcconfig injects into Info.plist.
    public static func fromMainBundle() throws -> TideEnvironment {
        guard
            let group = Bundle.main.object(forInfoDictionaryKey: "TideAppGroup") as? String,
            let keychain = Bundle.main.object(forInfoDictionaryKey: "TideKeychainGroup") as? String
        else { throw TideEnvironmentError.missingInfoPlistKeys }
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw TideEnvironmentError.appGroupUnavailable(group)
        }
        let directory = root.appending(path: "Library/Application Support/Tide", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: FileProtection.directoryAttributes
        )
        return TideEnvironment(appGroupID: group, keychainGroup: keychain, containerURL: directory)
    }

    public var bookmarkURL: URL { containerURL.appending(path: "vault.bookmark") }
    public var gitDirectoryURL: URL { containerURL.appending(path: "repo.git", directoryHint: .isDirectory) }
    public var repositoryURL: URL { containerURL.appending(path: "repository.json") }
    public var spikeLogURL: URL { containerURL.appending(path: "spike-log.jsonl") }
    public var runtimeProbeURL: URL { containerURL.appending(path: "runtime-probe.json") }
    public var lockProbeURL: URL { containerURL.appending(path: "lock-probe") }
}

/// Files in the app container use `completeUntilFirstUserAuthentication` so background sync can read them
/// while the device is locked (after the first unlock since boot).
enum FileProtection {
    static var directoryAttributes: [FileAttributeKey: Any] {
        #if os(iOS)
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        #else
        [:]
        #endif
    }

    static var writingOptions: Data.WritingOptions {
        #if os(iOS)
        [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
        [.atomic]
        #endif
    }
}
