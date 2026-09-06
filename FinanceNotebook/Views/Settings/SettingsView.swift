import SwiftUI
import SwiftData

/// Small on purpose. Settings exists because backup and restore need a sensible
/// home, not as a place to start collecting preferences.
struct SettingsView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var shareURL: URL?
    @State private var isImporting = false
    @State private var pendingBackup: BackupValidator.Validated?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                // Section has no title-plus-footer initialiser; the header has
                // to be given explicitly when a footer is present.
                Section {
                    Button {
                        exportBackup()
                    } label: {
                        Label("Export Backup", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("exportBackupButton")

                    Button {
                        isImporting = true
                    } label: {
                        Label("Restore Backup", systemImage: "square.and.arrow.down")
                    }
                    .accessibilityIdentifier("restoreBackupButton")
                } header: {
                    Text("DATA")
                } footer: {
                    Text("A backup is a complete copy of your notebook that this app can read back. A PDF report is not a backup.")
                }

                Section("ABOUT") {
                    LabeledContent("Backup Format",
                                   value: "Version \(FinanceNotebookBackup.currentFormatVersion)")
                        .accessibilityIdentifier("backupFormatVersion")
                    LabeledContent("Data Schema",
                                   value: "V\(FinanceNotebookBackup.currentSchemaVersion)")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("settingsView")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $shareURL) { url in
                ShareSheet(items: [url])
            }
            .sheet(isPresented: $isImporting) {
                BackupDocumentPicker(onPick: handleImport)
            }
            .sheet(item: $pendingBackup) { validated in
                RestoreBackupView(validated: validated) {
                    // The restore replaced everything, so nothing on screen
                    // should keep holding the old graph.
                    dismiss()
                }
            }
            .alert("Couldn't Read Backup",
                   isPresented: Binding(isPresent: $errorMessage)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func exportBackup() {
        do {
            shareURL = try BackupService.writeBackup(from: context)
        } catch {
            errorMessage = "The backup couldn't be created. Please try again."
        }
    }

    /// Validated before the user is offered anything. A file that cannot be
    /// restored never reaches a confirmation screen.
    private func handleImport(_ result: Result<Data, Error>) {
        isImporting = false
        switch result {
        case .failure:
            errorMessage = BackupError.malformedBackup.localizedDescription
        case .success(let data):
            do {
                pendingBackup = try BackupValidator.validate(data: data)
            } catch let error as BackupError {
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = BackupError.malformedBackup.localizedDescription
            }
        }
    }
}
