import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

#if DEBUG

// MARK: - NavigationBridge

/// Tracks navigation state (UINavigationController on iOS, NSWindowController on macOS).
@MainActor
final class NavigationBridge {
    private let queue = DispatchQueue(label: "com.appxray.nav", qos: .userInitiated)
    private var navigationPathBinding: NavigationPathBinding?
    private var stackNames: [String] = []

    struct NavigationPathBinding {
        var getStack: () -> [String]
        var push: (String) -> Void
        var pop: () -> Void
        var replace: (String) -> Void
    }

    struct SelectionBinding {
        var getCurrent: () -> String?
        var setSelection: (String) -> Void
        var getAvailable: () -> [String]
    }

    private var selectionBinding: SelectionBinding?

    init() {}

    func bindSwiftUIPath(_ binding: NavigationPathBinding) {
        navigationPathBinding = binding
    }

    func bindSelection(_ binding: SelectionBinding) {
        selectionBinding = binding
    }

    func getState() -> [String: Any] {
        if let binding = navigationPathBinding {
            let stack = binding.getStack()
            return [
                "currentRoute": ["name": stack.last ?? "root", "path": stack.last ?? "/"] as [String: Any],
                "stack": stack.enumerated().map { ["name": $0.element, "path": "/\($0.element)", "index": $0.offset] as [String: Any] },
                "availableRoutes": stack,
                "canGoBack": stack.count > 1,
                "canGoForward": false,
                "type": "stack",
            ] as [String: Any]
        }

        if let binding = selectionBinding {
            let current = binding.getCurrent() ?? "none"
            let available = binding.getAvailable()
            return [
                "currentRoute": ["name": current, "path": "/\(current)"] as [String: Any],
                "stack": [["name": current, "path": "/\(current)", "index": 0] as [String: Any]],
                "availableRoutes": available,
                "canGoBack": false,
                "canGoForward": false,
                "type": "selection",
            ] as [String: Any]
        }

        #if os(iOS)
        if let nav = findTopNavigationController() {
            let vcs = nav.viewControllers
            let names = vcs.map { String(describing: type(of: $0)) }
            let current = names.last ?? "unknown"
            return [
                "currentRoute": ["name": current, "path": "/\(current)"] as [String: Any],
                "stack": names.enumerated().map { ["name": $0.element, "path": "/\($0.element)", "index": $0.offset] as [String: Any] },
                "availableRoutes": names,
                "canGoBack": nav.viewControllers.count > 1,
                "canGoForward": false,
                "type": "uikit",
            ] as [String: Any]
        }
        #elseif os(macOS)
        if let window = ComponentInspector.bestWindow {
            let title = window.title
            return [
                "currentRoute": ["name": title, "path": "/"] as [String: Any],
                "stack": [["name": title, "path": "/", "index": 0] as [String: Any]],
                "availableRoutes": [title],
                "canGoBack": false,
                "canGoForward": false,
                "type": "window",
            ] as [String: Any]
        }
        #endif
        return [
            "currentRoute": ["name": "unknown", "path": "/"] as [String: Any],
            "stack": [] as [[String: Any]],
            "availableRoutes": [] as [String],
            "canGoBack": false,
            "canGoForward": false,
        ] as [String: Any]
    }

    func execute(params: [String: Any]) async -> [String: Any] {
        let action = params["action"] as? String ?? "push"
        let route = params["route"] as? String

        if let binding = navigationPathBinding {
            switch action {
            case "push":
                if let route = route {
                    binding.push(route)
                    // Yield to let SwiftUI process the state change before responding.
                    // Prevents timeout when the view update cycle is heavy.
                    await Task.yield()
                    return ["success": true]
                }
            case "pop", "goBack":
                binding.pop()
                await Task.yield()
                return ["success": true]
            case "replace":
                if let route = route {
                    binding.replace(route)
                    await Task.yield()
                    return ["success": true]
                }
            default:
                break
            }
        }

        if let binding = selectionBinding {
            switch action {
            case "select", "push", "replace":
                if let route = route {
                    binding.setSelection(route)
                    await Task.yield()
                    return ["success": true]
                }
                return ["success": false, "error": "route required for select action"]
            default:
                break
            }
        }

        #if os(iOS)
        if let nav = findTopNavigationController() {
            switch action {
            case "pop", "goBack":
                nav.popViewController(animated: true)
                return ["success": true]
            case "push":
                if route != nil {
                    return ["success": false, "error": "Push by route name requires SwiftUI binding"]
                }
            default:
                break
            }
        }
        #endif
        return ["success": false, "error": "Navigation not available — call bindSwiftUIPath() or bindSelection() in your app setup"]
    }

    #if os(iOS)
    private func findTopNavigationController() -> UINavigationController? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }),
              let root = window.rootViewController else {
            return nil
        }
        return findNavController(in: root)
    }

    private func findNavController(in vc: UIViewController) -> UINavigationController? {
        if let nav = vc as? UINavigationController { return nav }
        if let presented = vc.presentedViewController {
            if let nav = findNavController(in: presented) { return nav }
        }
        for child in vc.children {
            if let nav = findNavController(in: child) { return nav }
        }
        return nil
    }

    #endif
}

#endif
