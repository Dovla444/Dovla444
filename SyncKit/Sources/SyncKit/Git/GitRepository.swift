import Foundation
import libgit2

/// Thin wrapper around a libgit2 repository whose git directory lives in the app container
/// and whose work directory is the vault folder. Nothing git-related is ever written into the vault
/// except the note files themselves.
///
/// Not thread-safe: use one instance from one task at a time.
public final class GitRepository {
    public struct TransferStats: Sendable {
        public let objects: Int
        public let bytes: Int
    }

    private let pointer: OpaquePointer

    /// Opens the git directory, creating it if needed, and points it at `workDirectory`.
    ///
    /// The git directory is created as a bare repository and receives its work directory in memory
    /// on every open (`update_gitlink = 0`), so no `.git` file or folder ever appears in the vault.
    public init(gitDirectory: URL, workDirectory: URL) throws {
        _ = Git.initialized
        let gitPath = gitDirectory.path(percentEncoded: false)
        var repository: OpaquePointer?
        if FileManager.default.fileExists(atPath: gitDirectory.appending(path: "HEAD").path(percentEncoded: false)) {
            try Git.check(git_repository_open(&repository, gitPath), "open repository")
        } else {
            try FileManager.default.createDirectory(
                at: gitDirectory,
                withIntermediateDirectories: true,
                attributes: FileProtection.directoryAttributes
            )
            try Git.check(git_repository_init(&repository, gitPath, 1), "create repository")
        }
        guard let repository else {
            throw GitError(code: -1, operation: "open repository", message: "no repository returned")
        }
        pointer = repository
        try Git.check(git_repository_set_workdir(pointer, workDirectory.path(percentEncoded: false), 0), "set work directory")
    }

    deinit {
        git_repository_free(pointer)
    }

    /// Adds `origin` or updates its URL.
    public func setOrigin(_ url: URL) throws {
        var remote: OpaquePointer?
        if git_remote_lookup(&remote, pointer, "origin") == 0 {
            git_remote_free(remote)
            try Git.check(git_remote_set_url(pointer, "origin", url.absoluteString), "update remote")
        } else {
            try Git.check(git_remote_create(&remote, pointer, "origin", url.absoluteString), "add remote")
            git_remote_free(remote)
        }
    }

    /// Fetches all branches from `origin`. The token is sent as the HTTPS basic-auth password;
    /// pass nil for local remotes. A rejected token fails after one attempt instead of looping.
    public func fetchOrigin(token: String?) throws -> TransferStats {
        var remote: OpaquePointer?
        try Git.check(git_remote_lookup(&remote, pointer, "origin"), "find remote")
        defer { git_remote_free(remote) }

        var options = git_fetch_options()
        try Git.check(git_fetch_options_init(&options, UInt32(GIT_FETCH_OPTIONS_VERSION)), "fetch options")
        let credentials = Unmanaged.passRetained(CredentialPayload(token: token))
        defer { credentials.release() }
        options.callbacks.payload = credentials.toOpaque()
        options.callbacks.credentials = { out, _, _, _, payload in
            guard let payload else { return GIT_EUSER.rawValue }
            let credentials = Unmanaged<CredentialPayload>.fromOpaque(payload).takeUnretainedValue()
            guard let token = credentials.token, credentials.attempts == 0 else { return GIT_EUSER.rawValue }
            credentials.attempts += 1
            return git_credential_userpass_plaintext_new(out, "x-access-token", token)
        }

        try Git.check(git_remote_fetch(remote, nil, &options, nil), "fetch")
        let stats = git_remote_stats(remote).pointee
        return TransferStats(objects: Int(stats.total_objects), bytes: Int(stats.received_bytes))
    }

    /// Points the local branch at `origin/<branch>` and writes its files into the vault.
    ///
    /// Safe checkout: a file that already exists in the vault is never overwritten or deleted.
    /// Such paths are returned (libgit2 reports them even when the content is identical).
    public func checkoutRemoteBranch(_ branch: String) throws -> [String] {
        var remoteBranch: OpaquePointer?
        try Git.check(git_reference_lookup(&remoteBranch, pointer, "refs/remotes/origin/\(branch)"), "find remote branch")
        defer { git_reference_free(remoteBranch) }
        guard let target = git_reference_target(remoteBranch) else {
            throw GitError(code: -1, operation: "find remote branch", message: "branch has no target")
        }
        var commit: OpaquePointer?
        try Git.check(git_commit_lookup(&commit, pointer, target), "find commit")
        defer { git_commit_free(commit) }

        var localBranch: OpaquePointer?
        try Git.check(git_branch_create(&localBranch, pointer, branch, commit, 1), "create branch")
        git_reference_free(localBranch)

        var options = git_checkout_options()
        try Git.check(git_checkout_options_init(&options, UInt32(GIT_CHECKOUT_OPTIONS_VERSION)), "checkout options")
        options.checkout_strategy = GIT_CHECKOUT_SAFE.rawValue | GIT_CHECKOUT_ALLOW_CONFLICTS.rawValue
        options.notify_flags = GIT_CHECKOUT_NOTIFY_CONFLICT.rawValue
        let skipped = Unmanaged.passRetained(PathCollector())
        defer { skipped.release() }
        options.notify_payload = skipped.toOpaque()
        options.notify_cb = { _, path, _, _, _, payload in
            if let path, let payload {
                Unmanaged<PathCollector>.fromOpaque(payload).takeUnretainedValue().paths.append(String(cString: path))
            }
            return 0
        }

        // Checkout before moving HEAD so libgit2 compares against an empty baseline and treats
        // every existing vault file as untracked (never overwritten).
        try Git.check(git_checkout_tree(pointer, commit, &options), "write files")
        try Git.check(git_repository_set_head(pointer, "refs/heads/\(branch)"), "set head")
        return skipped.takeUnretainedValue().paths
    }
}

private final class CredentialPayload {
    let token: String?
    var attempts = 0

    init(token: String?) {
        self.token = token
    }
}

private final class PathCollector {
    var paths: [String] = []
}
