import Foundation
import Combine

#if DEBUG

final class StateBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.appxray.state", qos: .userInitiated)
    private var observables: [String: WeakRef] = [:]
    private var setters: [String: (Any) -> Void] = [:]

    struct WeakRef {
        weak var object: AnyObject?
    }

    /// Execute a block on the internal serial queue, but avoid deadlock
    /// when already on the main thread (which happens when callers use
    /// `await MainActor.run` to safely access @MainActor objects).
    private func syncSafe<T>(_ block: () -> T) -> T {
        if Thread.isMainThread {
            return block()
        }
        return queue.sync { block() }
    }

    func registerObservable(_ obj: Any, name: String, setters: [String: (Any) -> Void]? = nil) {
        syncSafe {
            guard let obj = obj as? AnyObject else { return }
            observables[name] = WeakRef(object: obj)
            if let setters = setters {
                for (key, setter) in setters {
                    self.setters["\(name).\(key)"] = setter
                }
            }
        }
    }

    func get(path: String, depth: Int?) -> [String: Any]? {
        syncSafe {
            if path.isEmpty { return snapshot() }
            let parts = path.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            let storeName = String(parts[0])
            let restPath = parts.count > 1 ? String(parts[1]) : ""
            guard let ref = observables[storeName], let obj = ref.object else {
                return ["error": "Store not found: \(storeName)"]
            }
            let value = getValue(at: restPath, from: obj, depth: depth ?? 10)
            return [
                "path": path, "value": serializeValue(value), "type": typeName(of: value),
                "mutable": true, "subscribers": [] as [String],
            ] as [String: Any]
        }
    }

    func set(path: String, value: Any, merge: Bool?) -> [String: Any]? {
        syncSafe {
            let parts = path.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            let storeName = String(parts[0])
            let restPath = parts.count > 1 ? String(parts[1]) : ""
            guard let ref = observables[storeName], let obj = ref.object else {
                return ["success": false, "error": "Store not found"]
            }
            if restPath.isEmpty {
                if let o = obj as? NSObject, o.responds(to: Selector(("setValue:forKey:"))) {
                    o.setValue(value, forKey: "value")
                }
                return ["success": true]
            }
            let result = setValue(value, at: restPath, on: obj, merge: merge ?? false, storeName: storeName)
            if result.success {
                return ["success": true]
            }
            return ["success": false, "error": result.error ?? "Failed to set value"]
        }
    }

    func snapshot() -> [String: Any] {
        var result: [String: Any] = [:]
        for (name, ref) in observables {
            guard let obj = ref.object else { continue }
            result[name] = serializeValue(getValue(at: "", from: obj, depth: 10))
        }
        return ["stores": result]
    }

    func restore(_ snapshot: [String: Any]) {
        syncSafe {
            guard let stores = snapshot["stores"] as? [String: Any] else { return }
            for (name, value) in stores {
                guard let ref = observables[name], let obj = ref.object else { continue }
                _ = setValue(value, at: "", on: obj, merge: false)
            }
        }
    }

    func listStores() -> [String] {
        syncSafe {
            observables.compactMap { $0.value.object != nil ? $0.key : nil }
        }
    }

    // MARK: - Read

    private func getValue(at path: String, from obj: Any, depth: Int) -> Any? {
        if depth <= 0 { return nil }
        if path.isEmpty { return reflectValue(obj, depth: depth) }
        let value = getValueAtPath(obj, path)
        return reflectValue(value as Any, depth: depth)
    }

    private func getValueAtPath(_ obj: Any, _ path: String) -> Any? {
        var current: Any? = obj
        for segment in path.split(separator: ".") {
            let key = String(segment)
            current = getChild(current, key: key)
            if current == nil { return nil }
        }
        return current
    }

    private func getChild(_ obj: Any?, key: String) -> Any? {
        guard let obj = obj else { return nil }
        let mirror = Mirror(reflecting: obj)
        for child in mirror.children {
            if child.label == key { return child.value }
        }
        // Look for @Published backing property (_key) and unwrap
        let publishedKey = "_\(key)"
        for child in mirror.children {
            if child.label == publishedKey,
               String(describing: type(of: child.value)).hasPrefix("Published<") {
                return unwrapPublished(child.value)
            }
        }
        if let dict = obj as? [String: Any] { return dict[key] }
        if let nsObj = obj as? NSObject, isKVCSafe(key: key, on: nsObj) {
            return nsObj.value(forKey: key)
        }
        return nil
    }

    // MARK: - Write

    private struct SetResult {
        let success: Bool
        let error: String?
        static let ok = SetResult(success: true, error: nil)
        static func fail(_ msg: String) -> SetResult { SetResult(success: false, error: msg) }
    }

    private func setValue(_ value: Any, at path: String, on obj: Any, merge: Bool, storeName: String? = nil) -> SetResult {
        if path.isEmpty {
            if let o = obj as? NSObject, o.responds(to: Selector(("setValue:forKey:"))) {
                o.setValue(value, forKey: "value")
                return .ok
            }
            return .fail("Cannot set root value")
        }

        if let storeName = storeName {
            let fullPath = "\(storeName).\(path)"
            if let setter = setters[fullPath] {
                setter(value)
                notifyObjectWillChange(obj)
                return .ok
            }
        }

        let segments = path.split(separator: ".")
        guard let firstKey = segments.first else { return .fail("Empty path") }

        let publishedResult = setPublishedValue(value, key: String(firstKey), remainingPath: Array(segments.dropFirst()).map(String.init), on: obj, storeName: storeName)
        if publishedResult {
            notifyObjectWillChange(obj)
            return .ok
        }

        // KVC fallback — only for ObjC-representable values to avoid crashes on
        // Swift enums and other non-KVC types that throw unrecoverable NSExceptions.
        if let o = obj as? NSObject, o.responds(to: Selector(("setValue:forKeyPath:"))), isKVCSafeValue(value) {
            o.setValue(value, forKeyPath: path)
            return .ok
        }
        let propName = path.split(separator: ".").last.map(String.init) ?? path
        let name = storeName ?? "yourStore"
        return .fail("Property '\(propName)' is not KVC-compatible (Swift enum/struct). Register a setter:\n  AppXray.shared.registerObservableObject(obj, name: \"\(name)\", setters: [\"\(propName)\": { obj.\(propName) = $0 as! YourType }])")
    }

    /// Set a value on a @Published property using Mirror to access the underlying storage.
    private func setPublishedValue(_ value: Any, key: String, remainingPath: [String], on obj: Any, storeName: String? = nil) -> Bool {
        let mirror = Mirror(reflecting: obj)
        let publishedKey = "_\(key)"

        for child in mirror.children {
            guard child.label == publishedKey else { continue }
            guard String(describing: type(of: child.value)).hasPrefix("Published<") else { continue }

            if remainingPath.isEmpty {
                return setPublishedStorage(child.value, newValue: value, key: publishedKey, on: obj, storeName: storeName)
            } else {
                if let unwrapped = unwrapPublished(child.value) {
                    let nestedPath = remainingPath.joined(separator: ".")
                    return setValue(value, at: nestedPath, on: unwrapped, merge: false).success
                }
            }
        }
        return false
    }

    /// Write to @Published storage.
    /// Priority: explicit setters > Combine Subject.send > NSObject KVC (safe types only) > ObjC runtime ivar.
    private func setPublishedStorage(_ published: Any, newValue: Any, key: String, on obj: Any, storeName: String? = nil) -> Bool {
        let objRef = obj as AnyObject
        let propertyName = String(key.dropFirst())

        // Check namespaced key first (e.g. "appState.showSidebar"), then bare key
        if let storeName = storeName, let setter = setters["\(storeName).\(propertyName)"] {
            setter(newValue)
            return true
        }
        if let setter = setters[propertyName] {
            setter(newValue)
            return true
        }

        // Try setting via Combine's internal CurrentValueSubject.
        // Published<T> stores a Subject after first subscription; we can call send()
        // on it to update the value and notify all subscribers.
        if sendViaPublishedSubject(published, newValue: newValue) {
            return true
        }

        // NSObject KVC — only safe for ObjC-representable values.
        if let nsObj = obj as? NSObject, isKVCSafeValue(newValue) {
            let setterSel = Selector("set\(propertyName.prefix(1).uppercased())\(propertyName.dropFirst()):")
            if nsObj.responds(to: setterSel) {
                nsObj.setValue(newValue, forKey: propertyName)
                return true
            }
        }

        // ObjC runtime ivar: only for non-Published ivars.
        if !key.hasPrefix("_") {
            let cls: AnyClass = type(of: objRef)
            if let ivar = class_getInstanceVariable(cls, key) {
                let boxed: AnyObject
                switch newValue {
                case let o as AnyObject where !(newValue is Int) && !(newValue is Double) && !(newValue is Bool):
                    boxed = o
                case let s as String: boxed = s as NSString
                case let i as Int: boxed = i as NSNumber
                case let d as Double: boxed = d as NSNumber
                case let b as Bool: boxed = b as NSNumber
                default: return false
                }
                object_setIvar(objRef, ivar, boxed)
                return true
            }
        }

        return false
    }

    /// Try to set a @Published value by reaching into its CurrentValueSubject.
    /// When Published<T> has been subscribed to (common for @Published props bound
    /// to SwiftUI views), it stores a CurrentValueSubject<T, Never>.  We locate it
    /// and call send() with the new value, which triggers all Combine subscribers.
    private func sendViaPublishedSubject(_ published: Any, newValue: Any) -> Bool {
        guard let subject = extractSubject(from: published) else { return false }

        // Approach 1: Type-safe send via CurrentValueSubject<T, Never> for common types.
        // This is the most reliable path — it respects Combine's thread-safety and
        // properly notifies all subscribers.
        if sendTypedValue(subject, newValue) { return true }

        // Approach 2: ObjC-compatible send path for bridgeable types
        let subjectObj = subject as AnyObject
        if let nsSubject = subjectObj as? NSObject {
            let sendSel = NSSelectorFromString("send:")
            if nsSubject.responds(to: sendSel) && isKVCSafeValue(newValue) {
                nsSubject.perform(sendSel, with: newValue)
                return true
            }
        }

        // Approach 3: Direct ivar mutation on the subject's value storage
        let subjectClass: AnyClass = type(of: subjectObj)
        if let ivar = class_getInstanceVariable(subjectClass, "value") {
            if let boxed = newValue as? AnyObject {
                object_setIvar(subjectObj, ivar, boxed)
                return true
            }
        }

        return false
    }

    /// Type-safe send for common @Published property types.
    /// Handles String, Int, Double, Bool, optionals, and arrays without requiring
    /// the user to register explicit setters.
    private func sendTypedValue(_ subject: Any, _ newValue: Any) -> Bool {
        if let s = subject as? CurrentValueSubject<String, Never> {
            if let v = newValue as? String { s.send(v); return true }
        }
        if let s = subject as? CurrentValueSubject<String?, Never> {
            if let v = newValue as? String { s.send(v); return true }
            if newValue is NSNull { s.send(nil); return true }
        }
        if let s = subject as? CurrentValueSubject<Int, Never> {
            if let v = newValue as? Int { s.send(v); return true }
            if let v = newValue as? NSNumber { s.send(v.intValue); return true }
        }
        if let s = subject as? CurrentValueSubject<Double, Never> {
            if let v = newValue as? Double { s.send(v); return true }
            if let v = newValue as? NSNumber { s.send(v.doubleValue); return true }
        }
        if let s = subject as? CurrentValueSubject<Bool, Never> {
            if let v = newValue as? Bool { s.send(v); return true }
            if let v = newValue as? NSNumber { s.send(v.boolValue); return true }
        }
        if let s = subject as? CurrentValueSubject<[String], Never> {
            if let v = newValue as? [String] { s.send(v); return true }
        }
        if let s = subject as? CurrentValueSubject<[Int], Never> {
            if let v = newValue as? [Int] { s.send(v); return true }
        }
        return false
    }

    /// Extract the CurrentValueSubject from a Published<T> wrapper.
    /// Handles multiple internal structures across different Combine/Swift versions.
    private func extractSubject(from published: Any) -> Any? {
        let mirror = Mirror(reflecting: published)
        for child in mirror.children where child.label == "storage" {
            let storageMirror = Mirror(reflecting: child.value)
            if let first = storageMirror.children.first {
                if first.label == "publisher" || first.label == "some" {
                    let publisherMirror = Mirror(reflecting: first.value)
                    for pChild in publisherMirror.children {
                        if pChild.label == "subject" { return pChild.value }
                    }
                    // Some Combine versions nest the subject one level deeper
                    for pChild in publisherMirror.children {
                        let innerMirror = Mirror(reflecting: pChild.value)
                        for innerChild in innerMirror.children {
                            if innerChild.label == "subject" { return innerChild.value }
                        }
                    }
                }
                // .value(T) case — no subject available (pre-subscription)
            }
        }
        // Alternative path: walk all children looking for a subject
        for child in mirror.children {
            let childMirror = Mirror(reflecting: child.value)
            for grandchild in childMirror.children {
                if grandchild.label == "subject" { return grandchild.value }
            }
        }
        return nil
    }

    /// Returns true if `value` can safely be passed to KVC methods without risking
    /// an unrecoverable ObjC exception (e.g. Swift enums are NOT KVC-compatible).
    private func isKVCSafeValue(_ value: Any) -> Bool {
        switch value {
        case is NSNull, is NSNumber, is NSString, is NSArray, is NSDictionary, is NSDate:
            return true
        case is String, is Int, is Double, is Float, is Bool:
            return true
        case is [Any], is [String: Any]:
            return true
        case let o as AnyObject where o is NSObject:
            return true
        default:
            return false
        }
    }

    /// Returns true if KVC `value(forKey:)` is safe for this key on the given object.
    private func isKVCSafe(key: String, on obj: NSObject) -> Bool {
        let setterSel = Selector("set\(key.prefix(1).uppercased())\(key.dropFirst()):")
        let getterSel = Selector(key)
        return obj.responds(to: getterSel) || obj.responds(to: setterSel)
    }

    // MARK: - @Published Unwrap

    /// Unwrap a `Published<T>` property wrapper to extract the current value.
    /// Handles both `.value(T)` storage (pre-subscription) and `.publisher(Subject)` storage.
    private func unwrapPublished(_ published: Any) -> Any? {
        let mirror = Mirror(reflecting: published)
        for child in mirror.children where child.label == "storage" {
            return extractPublishedStorage(child.value)
        }
        return nil
    }

    private func extractPublishedStorage(_ storage: Any) -> Any? {
        let mirror = Mirror(reflecting: storage)
        // Published.Storage is an enum: .value(T) or .publisher(Publisher)
        if let first = mirror.children.first {
            if first.label == "publisher" || first.label == "some" {
                return extractPublisherValue(first.value)
            }
            // .value(T) case — the associated value is T directly
            return first.value
        }
        return nil
    }

    private func extractPublisherValue(_ publisher: Any) -> Any? {
        let mirror = Mirror(reflecting: publisher)
        for child in mirror.children {
            if child.label == "subject" {
                return extractSubjectValue(child.value)
            }
            // Some Combine versions store currentValue directly
            if child.label == "currentValue" || child.label == "value" {
                return child.value
            }
        }
        return nil
    }

    private func extractSubjectValue(_ subject: Any) -> Any? {
        let mirror = Mirror(reflecting: subject)
        for child in mirror.children {
            if child.label == "value" || child.label == "_value" || child.label == "currentValue" {
                return child.value
            }
        }
        // Walk one level deeper for lock-wrapped values
        for child in mirror.children {
            let innerMirror = Mirror(reflecting: child.value)
            for innerChild in innerMirror.children {
                if innerChild.label == "value" || innerChild.label == "currentValue" {
                    return innerChild.value
                }
            }
        }
        return nil
    }

    // MARK: - Notification

    /// Trigger objectWillChange on an ObservableObject to notify SwiftUI.
    private func notifyObjectWillChange(_ obj: Any) {
        let mirror = Mirror(reflecting: obj)
        for child in mirror.children {
            if child.label == "objectWillChange" || child.label == "_objectWillChange" {
                if let publisher = child.value as? ObservableObjectPublisher {
                    DispatchQueue.main.async { publisher.send() }
                    return
                }
            }
        }
        if let observable = obj as? any ObservableObject {
            if let publisher = observable.objectWillChange as? ObservableObjectPublisher {
                DispatchQueue.main.async { publisher.send() }
            }
        }
    }

    // MARK: - Reflection & Serialization

    private func reflectValue(_ value: Any, depth: Int) -> Any {
        if depth <= 0 { return ["_truncated": true] }
        let mirror = Mirror(reflecting: value)
        switch mirror.displayStyle {
        case .optional:
            if let v = mirror.children.first?.value as Any? { return reflectValue(v, depth: depth) }
            return NSNull()
        case .struct, .class:
            var dict: [String: Any] = [:]
            for child in mirror.children {
                guard let label = child.label else { continue }
                var resolvedLabel = label
                var resolvedValue = child.value

                // Unwrap @Published wrappers: _foo → foo with the actual current value
                if label.hasPrefix("_"),
                   String(describing: type(of: child.value)).hasPrefix("Published<") {
                    resolvedLabel = String(label.dropFirst())
                    if let unwrapped = unwrapPublished(child.value) {
                        resolvedValue = unwrapped
                    }
                }

                dict[resolvedLabel] = serializeValue(reflectValue(resolvedValue, depth: depth - 1))
            }
            return dict
        case .collection:
            var arr: [Any] = []
            for child in mirror.children {
                arr.append(serializeValue(reflectValue(child.value, depth: depth - 1)))
            }
            return arr
        case .dictionary:
            var dict: [String: Any] = [:]
            for child in mirror.children {
                if let (k, v) = child.value as? (Any, Any) {
                    dict[String(describing: k)] = serializeValue(reflectValue(v, depth: depth - 1))
                }
            }
            return dict
        case .enum:
            // Serialize enum by case name + associated value if present
            if mirror.children.isEmpty {
                return String(describing: value)
            }
            if let first = mirror.children.first {
                var result: [String: Any] = ["_case": first.label ?? String(describing: value)]
                result["_value"] = serializeValue(reflectValue(first.value, depth: depth - 1))
                return result
            }
            return String(describing: value)
        default:
            return value
        }
    }

    private func serializeValue(_ value: Any) -> Any {
        switch value {
        case is NSNull: return ["type": "null", "value": NSNull()] as [String: Any]
        case let v as String: return ["type": "string", "value": v] as [String: Any]
        case let v as Bool: return ["type": "boolean", "value": v] as [String: Any]
        case let v as Int: return ["type": "number", "value": v] as [String: Any]
        case let v as Double: return ["type": "number", "value": v] as [String: Any]
        case let v as [Any]: return ["type": "array", "value": v.map { serializeValue($0) }] as [String: Any]
        case let v as [String: Any]: return ["type": "object", "value": v] as [String: Any]
        case let v as Date: return ["type": "date", "value": v.timeIntervalSince1970] as [String: Any]
        default:
            if let dict = value as? [String: Any] { return ["type": "object", "value": dict] as [String: Any] }
            if let arr = value as? [Any] { return ["type": "array", "value": arr.map { serializeValue($0) }] as [String: Any] }
            return ["type": "unknown", "value": String(describing: value)] as [String: Any]
        }
    }

    private func typeName(of value: Any?) -> String {
        guard let value = value else { return "undefined" }
        switch value {
        case is NSNull: return "null"
        case is String: return "string"
        case is Bool: return "boolean"
        case is Int, is Double, is Float: return "number"
        case is [Any]: return "array"
        case is [String: Any]: return "object"
        case is Date: return "date"
        default: return String(describing: type(of: value))
        }
    }
}

#endif
