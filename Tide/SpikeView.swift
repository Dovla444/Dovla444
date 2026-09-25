import SwiftUI
import SyncKit
import UniformTypeIdentifiers

/// Phase 0 test bench. Not the real UI: it exists to answer the spike questions on a device.
struct SpikeView: View {
    @State private var model = SpikeModel()
    @State private var choosingFolder = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                if let error = model.setupError {
                    Section {
                        Label(error, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                    }
                }
                if let message = model.message {
                    Section {
                        Text(message).font(.callout).textSelection(.enabled)
                    }
                }
                vaultSection
                gitHubSection
                runtimeSection
                logSection
            }
            .navigationTitle("Tide Spike")
            .refreshable { model.refresh() }
            .overlay {
                if let busy = model.busy {
                    ProgressView(busy)
                        .padding()
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
                }
            }
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                model.folderPicked(result)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { model.refresh() }
            }
            .task { await model.loadRepositories() }
        }
    }

    private var vaultSection: some View {
        Section {
            LabeledContent("Folder", value: model.folderName ?? "Not chosen")
            Button("Choose Folder…", systemImage: "folder") { choosingFolder = true }
            Button("Append Test Line", systemImage: "text.append") {
                Task { await model.appendLine() }
            }
            .disabled(model.folderName == nil)
        } header: {
            Text("Vault folder")
        } footer: {
            Text("Pick On My iPhone › Obsidian › your vault. The line goes to Tide-Spike.md.")
        }
    }

    private var gitHubSection: some View {
        Section {
            LabeledContent("Token", value: model.hasToken ? "Saved in Keychain" : "None")
            SecureField("Paste fine-grained token", text: $model.tokenInput)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Save and Check Token", systemImage: "key") {
                Task { await model.saveToken() }
            }
            .disabled(model.tokenInput.isEmpty)
            if !model.repositories.isEmpty {
                Picker("Repository", selection: Binding(get: { model.selectedRepository }, set: { model.select($0) })) {
                    ForEach(model.repositories) { repository in
                        Text(repository.fullName).tag(Optional(repository))
                    }
                }
            }
            Button("Clone Into Container (Measure)", systemImage: "arrow.down.doc") {
                Task { await model.clone() }
            }
            .disabled(!model.hasToken || model.selectedRepository == nil || model.folderName == nil)
            Button("Fetch (Measure)", systemImage: "arrow.down.circle") {
                Task { await model.fetch() }
            }
            .disabled(!model.hasToken || model.folderName == nil)
        } header: {
            Text("GitHub")
        } footer: {
            Text("Clone writes only missing files into the vault; existing files are never overwritten.")
        }
    }

    private var runtimeSection: some View {
        Section("Background runtime") {
            if let probe = model.runtimeProbe {
                LabeledContent("Trigger", value: probe.trigger)
                LabeledContent("Process", value: probe.process)
                LabeledContent("Ran for", value: Duration.seconds(probe.seconds).formatted(.units(allowed: [.minutes, .seconds])))
                LabeledContent("Ending", value: probe.ending ?? "killed by iOS")
            } else {
                Text("Run the “Measure Runtime” shortcut, then come back.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var logSection: some View {
        Section {
            ForEach(model.events) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.action).font(.headline)
                    Text(event.outcome).font(.callout).textSelection(.enabled)
                    Text(detail(for: event)).font(.caption).foregroundStyle(.secondary)
                }
            }
            if !model.events.isEmpty {
                Button("Clear Log", role: .destructive) { model.clearLog() }
            }
        } header: {
            Text("Log")
        }
    }

    private func detail(for event: SpikeEvent) -> String {
        let lock = switch event.deviceLocked {
        case .some(true): "locked"
        case .some(false): "unlocked"
        case .none: "lock state unknown"
        }
        let seconds = event.seconds.map { $0.formatted(.number.precision(.fractionLength(2))) + " s" } ?? ""
        return "\(event.date.formatted(date: .omitted, time: .standard)) · \(event.process) · \(lock) · \(seconds)"
    }
}

#Preview {
    SpikeView()
}
