import Foundation

public enum VaultAccessError: Error, CustomStringConvertible {
    case noFolderChosen
    case folderLost(String)
    case accessDenied

    public var description: String {
        switch self {
        case .noFolderChosen: "No vault folder chosen yet"
        case .folderLost(let reason): "Can't find the vault folder (\(reason)). Choose it again."
        case .accessDenied: "Access to the vault folder was denied. Choose it again."
        }
    }
}

/// Persists the security-scoped bookmark of the vault folder in the App Group so the app,
/// the widget extension and App Intents can all reach the folder.
public struct VaultBookmarkStore: Sendable {
    let fileURL: URL

    public init(environment: TideEnvironment) {
        fileURL = environment.bookmarkURL
    }

    public var hasBookmark: Bool {
        FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false))
    }

    /// Stores a bookmark for a URL returned by the system folder picker.
    public func save(pickedURL url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        try write(bookmarkFor: url)
    }

    /// Resolves the bookmark, re-saves it when stale and runs `body` inside security-scoped access.
    /// If the folder can't be resolved nothing is touched and the error says to choose it again.
    public func withVaultAccess<T>(_ body: (URL) throws -> T) throws -> T {
        guard let data = try? Data(contentsOf: fileURL) else { throw VaultAccessError.noFolderChosen }
        var isStale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        } catch {
            throw VaultAccessError.folderLost(error.localizedDescription)
        }
        guard url.startAccessingSecurityScopedResource() else { throw VaultAccessError.accessDenied }
        defer { url.stopAccessingSecurityScopedResource() }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue
        else { throw VaultAccessError.folderLost("missing") }

        if isStale {
            try write(bookmarkFor: url)
        }
        return try body(url)
    }

    private func write(bookmarkFor url: URL) throws {
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        try data.write(to: fileURL, options: FileProtection.writingOptions)
    }
}
