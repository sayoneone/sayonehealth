import SwiftUI

// The ONLY place for watchOS-11-only APIs in the watch app (D23). If the target ever drops to
// watchOS 10 (R6), wrap these bodies in `if #available(watchOS 11.0, *)`.

extension View {
    /// Double tap (watchOS 11, Series 9+ / Ultra 2) activates the modified button.
    /// Use on at most one button per screen.
    func watchPrimaryAction() -> some View {
        handGestureShortcut(.primaryAction)
    }

    /// Same as `watchPrimaryAction()`, but only active when `enabled` is true, so a list of
    /// identical rows keeps one stable view type while exactly one row owns the double tap.
    func watchPrimaryAction(enabled: Bool) -> some View {
        handGestureShortcut(.primaryAction, isEnabled: enabled)
    }
}
