import SwiftUI
#if DEBUG
import AppXray
#endif

extension View {
    /// Assign a stable test ID for both AppXray (debug) and accessibility (release).
    /// In DEBUG builds, uses AppXray's `.xrayId()` for O(1) lookup + accessibility.
    /// In release builds, falls back to `.accessibilityIdentifier()`.
    func testID(_ id: String) -> some View {
        #if DEBUG
        return self.xrayId(id)
        #else
        return self.accessibilityIdentifier(id)
        #endif
    }
}
