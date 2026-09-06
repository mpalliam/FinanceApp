import SwiftUI
import UniformTypeIdentifiers

/// The system file importer, wrapped so a backup can be chosen from Files,
/// iCloud Drive, or wherever the user put it.
///
/// The chosen file is read into memory immediately, inside its security scope.
/// A URL handed over by the picker is only readable while that scope is held,
/// and holding one open across a confirmation screen would be a way to be
/// surprised later.
struct BackupDocumentPicker: UIViewControllerRepresentable {

    let onPick: (Result<Data, Error>) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Backups are JSON under a custom extension; allow both so a file
        // renamed on the way through Files can still be opened.
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.json, .data], asCopy: true
        )
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController,
                                context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {

        private let onPick: (Result<Data, Error>) -> Void

        init(onPick: @escaping (Result<Data, Error>) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onPick(.failure(BackupError.malformedBackup))
                return
            }

            // asCopy gives a file in the app's own container, but ask for the
            // scope anyway: it costs nothing and the provider is free to hand
            // back something scoped.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            do {
                onPick(.success(try Data(contentsOf: url)))
            } catch {
                onPick(.failure(BackupError.malformedBackup))
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
