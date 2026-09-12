import SwiftUI

/// Shown when the local store cannot be opened at launch.
///
/// The alternative was crashing, which tells the user nothing and leaves them
/// with an app that dies on every launch. A notebook that cannot open its own
/// store is in real trouble, but the user still has a decision to make -- their
/// backups are readable by a reinstalled app -- so the screen says that plainly
/// instead of showing a SwiftData error they cannot act on.
struct StoreUnavailableView: View {

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't Open Your Notebook", systemImage: "exclamationmark.triangle")
        } description: {
            Text("""
                 Finance Notebook couldn't open the data stored on this device.

                 Restarting your iPhone may fix it. If it doesn't, reinstalling \
                 the app clears the stored data and lets you restore from a \
                 backup you exported earlier.
                 """)
        }
        .accessibilityIdentifier("storeUnavailableView")
    }
}
