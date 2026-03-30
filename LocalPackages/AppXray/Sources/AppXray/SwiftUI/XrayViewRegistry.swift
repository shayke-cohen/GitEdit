import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

#if DEBUG

/// Registry entry storing frame info for a view with an xray ID.
struct XrayEntry {
    var frame: CGRect
}

/// Registry mapping xray IDs to view frame information for O(1) lookup.
/// Used by `View.xrayId(_:)` to bypass accessibility layer limitations on macOS.
///
/// Registration happens during the `xrayId()` extension method call, which
/// executes as part of SwiftUI view body evaluation. This is reliable because
/// view bodies are re-evaluated whenever state changes trigger a re-render.
final class XrayViewRegistry {
    static let shared = XrayViewRegistry()

    private var entries: [String: XrayEntry] = [:]

    private init() {}

    func register(_ id: String, frame: CGRect) {
        entries[id] = XrayEntry(frame: frame)
    }

    func updateFrame(_ id: String, frame: CGRect) {
        entries[id] = XrayEntry(frame: frame)
    }

    /// Look up an xray ID. Returns the frame if the view is registered.
    func lookup(_ id: String) -> CGRect? {
        guard let entry = entries[id] else { return nil }
        return entry.frame
    }

    /// Check if an ID is registered.
    func contains(_ id: String) -> Bool {
        entries[id] != nil
    }

    func unregister(_ id: String) {
        entries.removeValue(forKey: id)
    }

    /// All currently registered IDs.
    var allIds: [String] { Array(entries.keys) }
}

#endif
