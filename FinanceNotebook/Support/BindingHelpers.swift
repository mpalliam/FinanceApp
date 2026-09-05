import SwiftUI

extension Binding where Value == Bool {

    /// Presents while an optional has a value, and clears it on dismissal.
    ///
    /// Using `.constant(x != nil)` looks equivalent but is one-way: SwiftUI
    /// cannot put the sheet or dialog away by itself, so anything that
    /// dismisses without running a button action leaves it stuck open.
    init<Wrapped>(isPresent optional: Binding<Wrapped?>) {
        self.init(
            get: { optional.wrappedValue != nil },
            set: { presented in
                if !presented { optional.wrappedValue = nil }
            }
        )
    }
}
