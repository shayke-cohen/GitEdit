import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

#if DEBUG

@MainActor
final class ScreenshotEngine {

    func capture(params: [String: Any]) async -> [String: Any] {
        let format = (params["format"] as? String) ?? "png"

        #if os(iOS)
        return captureIOS(format: format)
        #elseif os(macOS)
        return captureMacOS(format: format)
        #endif
    }

    #if os(iOS)
    private func captureIOS(format: String) -> [String: Any] {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else {
            return ["error": "No key window"]
        }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { ctx in
            window.layer.render(in: ctx.cgContext)
        }

        let data: Data?
        if format == "jpeg" {
            data = image.jpegData(compressionQuality: 0.85)
        } else {
            data = image.pngData()
        }

        guard let imageData = data else { return ["error": "Failed to render"] }

        return [
            "image": imageData.base64EncodedString(),
            "width": Int(window.bounds.width),
            "height": Int(window.bounds.height),
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "format": format,
        ]
    }
    #elseif os(macOS)
    private func captureMacOS(format: String) -> [String: Any] {
        // Prefer keyWindow so we capture sheets/popovers when they are
        // the frontmost surface. This also avoids cacheDisplay blocking
        // when the main window's contentView is obscured by a sheet.
        let window = NSApplication.shared.keyWindow ?? ComponentInspector.bestWindow
        guard let window, let contentView = window.contentView else {
            return ["error": "No window"]
        }

        let bounds = contentView.bounds
        guard bounds.width > 0, bounds.height > 0 else {
            return ["error": "Window has zero size"]
        }

        guard let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            return ["error": "Failed to create bitmap"]
        }
        contentView.cacheDisplay(in: bounds, to: rep)

        let data: Data?
        if format == "jpeg" {
            data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        } else {
            data = rep.representation(using: .png, properties: [:])
        }

        guard let imageData = data else { return ["error": "Failed to render"] }

        return [
            "image": imageData.base64EncodedString(),
            "width": Int(bounds.width),
            "height": Int(bounds.height),
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "format": format,
        ]
    }
    #endif
}

#endif
