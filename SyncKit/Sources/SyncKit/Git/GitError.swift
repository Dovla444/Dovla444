import libgit2

public struct GitError: Error, CustomStringConvertible {
    public let code: Int32
    public let operation: String
    public let message: String

    public var description: String { "\(operation) failed (\(code)): \(message)" }

    /// libgit2 reports HTTP 401/403 as a generic error; the message tells them apart.
    public var isAuthenticationFailure: Bool {
        code == GIT_EAUTH.rawValue || message.contains("401") || message.contains("403")
    }
}

enum Git {
    /// libgit2 must be initialised once per process before any other call.
    static let initialized: Void = {
        git_libgit2_init()
        return ()
    }()

    static func check(_ code: Int32, _ operation: String) throws {
        guard code < 0 else { return }
        throw GitError(code: code, operation: operation, message: lastErrorMessage())
    }

    static func lastErrorMessage() -> String {
        guard let error = git_error_last(), let message = error.pointee.message else { return "unknown error" }
        return String(cString: message)
    }
}
