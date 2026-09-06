import SwiftUI
import UIKit

/// The system share sheet.
///
/// A thin wrapper around UIActivityViewController rather than a package: this
/// is the one piece of UIKit the app needs, and everything the sheet does --
/// Files, Mail, Print, AirDrop -- comes free with it.
///
/// The file stays on disk for as long as this view lives, because the activity
/// controller reads it lazily and deleting it early would hand the user an
/// empty document.
struct ShareSheet: UIViewControllerRepresentable {

    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
