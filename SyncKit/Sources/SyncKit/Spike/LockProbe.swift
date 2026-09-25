import Foundation

/// Detects whether the device is locked from any process (app or extension) by trying to read a file
/// written with `complete` data protection, which is unreadable while the device is locked.
public struct LockProbe: Sendable {
    let url: URL

    public init(environment: TideEnvironment) {
        url = environment.lockProbeURL
    }

    /// Call from the app while it's in the foreground (device unlocked).
    public func install() {
        #if os(iOS)
        try? Data("probe".utf8).write(to: url, options: [.atomic, .completeFileProtection])
        #endif
    }

    /// true = locked, false = unlocked, nil = probe not installed yet.
    public func isDeviceLocked() -> Bool? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return (try? Data(contentsOf: url)) == nil
    }
}
