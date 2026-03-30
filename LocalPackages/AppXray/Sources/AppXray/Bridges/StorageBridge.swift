import Foundation
import Security

#if DEBUG

// MARK: - StorageBridge

/// Local storage access: UserDefaults, Keychain, FileManager.
final class StorageBridge {
    private let queue = DispatchQueue(label: "com.appxray.storage", qos: .userInitiated)

    func read(params: [String: Any]) async -> [String: Any] {
        let store = params["store"] as? String ?? "userDefaults"
        let key = params["key"] as? String

        switch store {
        case "userDefaults":
            return readUserDefaults(key: key)
        case "keychain":
            return readKeychain(key: key)
        case "files":
            return listSandbox(key: key)
        default:
            return ["error": "Unknown store: \(store)"]
        }
    }

    func write(params: [String: Any]) async -> [String: Any] {
        let store = params["store"] as? String ?? "userDefaults"
        let key = params["key"] as? String
        let value = params["value"]

        guard let key = key else {
            return ["success": false, "error": "key required"]
        }

        switch store {
        case "userDefaults":
            UserDefaults.standard.set(value, forKey: key)
            return ["success": true]
        case "keychain":
            return writeKeychain(key: key, value: value)
        default:
            return ["success": false, "error": "Store not supported for write"]
        }
    }

    func clear(params: [String: Any]) async -> [String: Any] {
        let store = params["store"] as? String ?? "userDefaults"
        let key = params["key"] as? String

        switch store {
        case "userDefaults":
            if let key = key {
                UserDefaults.standard.removeObject(forKey: key)
            } else {
                if let bundleId = Bundle.main.bundleIdentifier {
                    UserDefaults.standard.removePersistentDomain(forName: bundleId)
                }
            }
            return ["success": true]
        case "keychain":
            if let key = key {
                return deleteKeychain(key: key)
            }
            return ["success": false, "error": "key required for keychain clear"]
        default:
            return ["success": false, "error": "Store not supported"]
        }
    }

    func getAvailableStores() -> [String] {
        ["userDefaults", "keychain", "files"]
    }

    // MARK: - UserDefaults

    private func readUserDefaults(key: String?) -> [String: Any] {
        let defaults = UserDefaults.standard
        if let key = key {
            if let value = defaults.object(forKey: key) {
                return ["store": "userDefaults", "key": key, "value": serializeStorageValue(value), "type": typeOf(value)]
            }
            return ["error": "Key not found"]
        }
        let dict = defaults.dictionaryRepresentation()
        var entries: [[String: Any]] = []
        for (k, v) in dict {
            entries.append([
                "key": k,
                "value": serializeStorageValue(v),
                "type": typeOf(v),
            ] as [String: Any])
        }
        return ["store": "userDefaults", "entries": entries]
    }

    // MARK: - Keychain

    private func readKeychain(key: String?) -> [String: Any] {
        guard let key = key else {
            return ["error": "key required for keychain read"]
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            if let str = String(data: data, encoding: .utf8) {
                return ["store": "keychain", "key": key, "value": str, "type": "string"]
            }
            return ["store": "keychain", "key": key, "value": data.base64EncodedString(), "type": "binary"]
        }
        if status == errSecItemNotFound {
            return ["error": "Key not found"]
        }
        return ["error": "Keychain error: \(status)"]
    }

    private func writeKeychain(key: String, value: Any?) -> [String: Any] {
        var data: Data?
        if let str = value as? String {
            data = str.data(using: .utf8)
        } else if let json = value {
            data = (try? JSONSerialization.data(withJSONObject: json))
        }
        guard let data = data else {
            return ["success": false, "error": "Value must be string or JSON-serializable"]
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary) // ignore result
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return ["success": status == errSecSuccess]
    }

    private func deleteKeychain(key: String) -> [String: Any] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return ["success": status == errSecSuccess || status == errSecItemNotFound]
    }

    // MARK: - FileManager (sandbox)

    private func listSandbox(key: String?) -> [String: Any] {
        let fm = FileManager.default
        let urls: [URL] = [
            fm.urls(for: .documentDirectory, in: .userDomainMask).first!,
            fm.urls(for: .libraryDirectory, in: .userDomainMask).first!,
            fm.temporaryDirectory,
        ]
        var dirs: [[String: Any]] = []
        for url in urls {
            let name = url.lastPathComponent
            var isDir: ObjCBool = false
            _ = fm.fileExists(atPath: url.path, isDirectory: &isDir)
            var count = 0
            if let contents = try? fm.contentsOfDirectory(atPath: url.path) {
                count = contents.count
            }
            dirs.append([
                "path": url.path,
                "name": name,
                "isDirectory": true,
                "childCount": count,
            ] as [String: Any])
        }
        return ["store": "files", "entries": dirs]
    }

    private func serializeStorageValue(_ value: Any) -> Any {
        if value is NSNull { return NSNull() }
        if let v = value as? String { return v }
        if let v = value as? Int { return v }
        if let v = value as? Double { return v }
        if let v = value as? Bool { return v }
        if let v = value as? Data { return v.base64EncodedString() }
        if let v = value as? [Any] { return v }
        if let v = value as? [String: Any] { return v }
        return String(describing: value)
    }

    private func typeOf(_ value: Any) -> String {
        switch value {
        case is NSNull: return "null"
        case is String: return "string"
        case is Int: return "number"
        case is Double: return "number"
        case is Bool: return "boolean"
        case is Data: return "binary"
        case is [Any]: return "array"
        case is [String: Any]: return "object"
        default: return "unknown"
        }
    }
}

#endif
