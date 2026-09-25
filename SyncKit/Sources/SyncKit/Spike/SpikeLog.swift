import Foundation

/// One line in the Phase 0 spike log: what ran, in which process, whether the device was locked, and how it went.
public struct SpikeEvent: Codable, Sendable, Identifiable {
    public let id: UUID
    public let date: Date
    /// Bundle identifier of the process that executed the action (app or widget extension).
    public let process: String
    public let action: String
    /// nil when the lock state could not be determined.
    public let deviceLocked: Bool?
    public let outcome: String
    public let seconds: Double?

    public init(action: String, deviceLocked: Bool?, outcome: String, seconds: Double?) {
        id = UUID()
        date = .now
        process = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        self.action = action
        self.deviceLocked = deviceLocked
        self.outcome = outcome
        self.seconds = seconds
    }
}

/// Append-only JSON-lines log in the App Group, readable by the app and the widget.
public struct SpikeLog: Sendable {
    let url: URL

    public init(environment: TideEnvironment) {
        url = environment.spikeLogURL
    }

    public func append(_ event: SpikeEvent) {
        guard var line = try? JSONEncoder.spike.encode(event) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url, options: FileProtection.writingOptions)
        }
    }

    public func recent(limit: Int = 50) -> [SpikeEvent] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let events = data.split(separator: 0x0A).compactMap { try? JSONDecoder.spike.decode(SpikeEvent.self, from: $0) }
        return Array(events.suffix(limit))
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

extension JSONEncoder {
    static var spike: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var spike: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
