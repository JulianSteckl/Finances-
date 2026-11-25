import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Back up, restore and export, shown in Plan settings.
struct BackupSection: View {
    @Environment(\.modelContext) private var modelContext
    /// Saves unsaved edits on the settings screen, so they're part of the backup.
    let saveEdits: () -> Void
    /// Reloads the settings screen, so leaving it doesn't write old values over restored ones.
    let reload: () -> Void

    @State private var pendingRestore: Backup?
    /// File name of the copy saved before the last restore, kept so Undo is still there later.
    @AppStorage("copyBeforeLastRestore") private var copyName = ""
    @State private var message: String?
    @State private var problem: String?

    var body: some View {
        GroupBox("Backup") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Button("Back up…", action: backUp).buttonStyle(PrimaryButtonStyle())
                    Button("Restore…", action: chooseBackup).buttonStyle(SecondaryButtonStyle())
                    Button("Export log…", action: exportLog).buttonStyle(SecondaryButtonStyle())
                    Spacer(minLength: 0)
                }
                if message != nil || !copyName.isEmpty {
                    HStack(spacing: 10) {
                        if let message { Label(message, systemImage: "checkmark.circle.fill") }
                        if !copyName.isEmpty { Button("Undo restore…", action: chooseCopy).buttonStyle(.link) }
                    }
                    .font(.callout)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog(
            "Replace everything with this backup?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            presenting: pendingRestore
        ) { backup in
            Button("Replace with backup", role: .destructive) { restore(backup) }
        } message: { backup in
            Text("It's from \(backup.savedAt.formatted(date: .long, time: .shortened)) and has \(Self.count(backup.entries.count)). Your current plan and log will be replaced.")
        }
        .alert("That didn't work", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(problem ?? "")
        }
    }

    private static func fileName(_ name: String, now: Date = .now) -> String {
        "\(name) \(now.formatted(.verbatim("\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)", timeZone: .current, calendar: .current)))"
    }

    private static func count(_ entries: Int) -> String { entries == 1 ? "1 entry" : "\(entries) entries" }

    private func backUp() {
        saveEdits()
        attempt {
            let backup = try Backup(context: modelContext)
            if try save(backup.data(), name: Self.fileName("Finances backup"), type: .json) {
                message = "Backed up \(Self.count(backup.entries.count))"
            }
        }
    }

    private func exportLog() {
        attempt {
            let entries = try modelContext.fetch(FetchDescriptor<MoneyEntry>())
            if try save(Data(LogExport.csv(entries).utf8), name: Self.fileName("Finances log"), type: .commaSeparatedText) {
                message = "Exported \(Self.count(entries.count))"
            }
        }
    }

    private func chooseBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a Finances backup"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        attempt { pendingRestore = try Backup(data: Data(contentsOf: url)) }
    }

    private func restore(_ backup: Backup) {
        attempt {
            saveEdits()
            // No copy of the current data, no restore.
            let current = try Backup(context: modelContext).data()
            let copy = try Self.keepCopy(current)
            try backup.restore(into: modelContext)
            copyName = copy
            message = "Restored \(Self.count(backup.entries.count))"
            reload()
        }
    }

    /// Undo goes through the same confirmation as any restore, so it can be undone too.
    private func chooseCopy() {
        attempt { pendingRestore = try Backup(data: Data(contentsOf: Self.copiesFolder.appending(path: copyName))) }
    }

    /// Returns false when the user cancels.
    private func save(_ data: Data, name: String, type: UTType) throws -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        try data.write(to: url, options: .atomic)
        return true
    }

    private static var copiesFolder: URL {
        .applicationSupportDirectory.appending(path: "Finances Backups", directoryHint: .isDirectory)
    }

    /// Saves the data a restore is about to replace, and returns its file name.
    private static func keepCopy(_ data: Data) throws -> String {
        try FileManager.default.createDirectory(at: copiesFolder, withIntermediateDirectories: true)
        let name = "Before restore \(UUID().uuidString).json"
        try data.write(to: copiesFolder.appending(path: name), options: .atomic)
        return name
    }

    private func attempt(_ action: () throws -> Void) {
        message = nil
        do { try action() } catch { problem = error.localizedDescription }
    }
}
