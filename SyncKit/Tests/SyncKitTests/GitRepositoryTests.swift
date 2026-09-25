#if os(macOS)
import Foundation
import Testing
@testable import SyncKit

/// Phase 0 checks of the two libgit2 assumptions the whole design rests on.
/// Run with `swift test` in SyncKit/ on a Mac (uses /usr/bin/git only to build the fixture origin).
@Suite struct GitRepositoryTests {
    @Test func gitDirectoryStaysOutsideTheVault() throws {
        let sandbox = try Sandbox()
        let origin = try sandbox.makeOrigin(files: ["Note.md": "a\nb\n", ".obsidian/app.json": "{}\n"])
        let vault = try sandbox.makeVault(files: ["Existing.md": "local only\n"])

        let repository = try GitRepository(gitDirectory: sandbox.gitDirectory, workDirectory: vault)
        try repository.setOrigin(origin)
        _ = try repository.fetchOrigin(token: nil)
        let untouched = try repository.checkoutRemoteBranch("main")

        #expect(untouched.isEmpty)
        #expect(try sandbox.read(vault, "Note.md") == "a\nb\n")
        #expect(try sandbox.read(vault, ".obsidian/app.json") == "{}\n")
        #expect(try sandbox.read(vault, "Existing.md") == "local only\n")
        #expect(!FileManager.default.fileExists(atPath: vault.appending(path: ".git").path(percentEncoded: false)))
    }

    @Test func existingVaultFilesAreNeverOverwritten() throws {
        let sandbox = try Sandbox()
        let origin = try sandbox.makeOrigin(files: ["Note.md": "remote\n", "Same.md": "same\n"])
        let vault = try sandbox.makeVault(files: ["Note.md": "local\n", "Same.md": "same\n"])

        let repository = try GitRepository(gitDirectory: sandbox.gitDirectory, workDirectory: vault)
        try repository.setOrigin(origin)
        _ = try repository.fetchOrigin(token: nil)
        let untouched = try repository.checkoutRemoteBranch("main")

        #expect(Set(untouched) == ["Note.md", "Same.md"])
        #expect(try sandbox.read(vault, "Note.md") == "local\n")
        #expect(try sandbox.read(vault, "Same.md") == "same\n")
    }

    @Test func reopeningKeepsTheWorkDirectory() throws {
        let sandbox = try Sandbox()
        let origin = try sandbox.makeOrigin(files: ["Note.md": "a\n"])
        let vault = try sandbox.makeVault(files: [:])

        do {
            let repository = try GitRepository(gitDirectory: sandbox.gitDirectory, workDirectory: vault)
            try repository.setOrigin(origin)
            _ = try repository.fetchOrigin(token: nil)
            _ = try repository.checkoutRemoteBranch("main")
        }
        let reopened = try GitRepository(gitDirectory: sandbox.gitDirectory, workDirectory: vault)
        _ = try reopened.fetchOrigin(token: nil)
        #expect(try sandbox.read(vault, "Note.md") == "a\n")
    }
}

private struct Sandbox {
    let root: URL
    var gitDirectory: URL { root.appending(path: "container/repo.git", directoryHint: .isDirectory) }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "SyncKitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func makeOrigin(files: [String: String]) throws -> URL {
        let origin = root.appending(path: "origin", directoryHint: .isDirectory)
        try write(files, into: origin)
        try git(["init", "-q", "-b", "main"], in: origin)
        try git(["add", "-A"], in: origin)
        try git(["-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-q", "-m", "init"], in: origin)
        return origin
    }

    func makeVault(files: [String: String]) throws -> URL {
        let vault = root.appending(path: "vault", directoryHint: .isDirectory)
        try write(files, into: vault)
        return vault
    }

    func read(_ folder: URL, _ path: String) throws -> String {
        try String(contentsOf: folder.appending(path: path), encoding: .utf8)
    }

    private func write(_ files: [String: String], into folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (path, contents) in files {
            let url = folder.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url)
        }
    }

    private func git(_ arguments: [String], in folder: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = folder
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
#endif
