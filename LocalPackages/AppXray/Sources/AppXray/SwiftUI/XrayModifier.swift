import SwiftUI

#if DEBUG

public extension View {
    /// Assign an appxray test ID to this view for reliable element lookup.
    ///
    /// On macOS, SwiftUI's `.accessibilityIdentifier()` is not always queryable
    /// from the accessibility tree. `.xrayId()` registers the view in the SDK's
    /// internal registry for O(1) lookup, and also sets the standard
    /// `.accessibilityIdentifier()` for cross-platform compatibility.
    ///
    /// ```swift
    /// Button("Log In") { login() }
    ///     .xrayId("submit-login")
    /// ```
    ///
    /// On iOS, this is equivalent to `.accessibilityIdentifier()` with a small
    /// overhead. On macOS, it guarantees that `@testId("submit-login")` resolves.
    func xrayId(_ id: String) -> some View {
        XrayViewRegistry.shared.register(id, frame: .zero)
        return self.accessibilityIdentifier(id)
    }
}

#endif
