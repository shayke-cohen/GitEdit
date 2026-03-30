import Foundation

#if DEBUG

public enum TimelineCategory: String, Codable {
    case network
    case state
    case render
    case navigation
    case storage
    case error
    case console
    case interaction
    case trace
}

public struct TimelineSource: Codable {
    public var file: String?
    public var line: Int?
    public var component: String?
    public var function: String?
}

public struct TimelineEntry: Codable {
    public let id: String
    public let timestamp: Double
    public let category: TimelineCategory
    public let action: String
    public let summary: String
    public var duration: Double?
    public var source: TimelineSource?
    public var data: [String: AnyCodable]?
}

public struct TimelineStats: Codable {
    public let totalEntries: Int
    public let windowMs: Int
    public let rates: [String: Int]
}

public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { value = s }
        else if let i = try? container.decode(Int.self) { value = i }
        else if let d = try? container.decode(Double.self) { value = d }
        else if let b = try? container.decode(Bool.self) { value = b }
        else if container.decodeNil() { value = NSNull() }
        else if let arr = try? container.decode([AnyCodable].self) { value = arr }
        else { value = try container.decode([String: AnyCodable].self) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let s as String: try container.encode(s)
        case let i as Int: try container.encode(i)
        case let d as Double: try container.encode(d)
        case let b as Bool: try container.encode(b)
        case is NSNull: try container.encodeNil()
        case let dict as [String: AnyCodable]: try container.encode(dict)
        case let arr as [AnyCodable]: try container.encode(arr)
        default: try container.encodeNil()
        }
    }
}

public final class TimelineBridge {
    private var buffer: [TimelineEntry?]
    private let capacity: Int
    private var head = 0
    private var count = 0
    private var idCounter = 0
    private let lock = NSLock()

    public init(capacity: Int = 2000) {
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
    }

    @discardableResult
    public func emit(
        category: TimelineCategory,
        action: String,
        summary: String,
        duration: Double? = nil,
        source: TimelineSource? = nil,
        data: [String: AnyCodable]? = nil
    ) -> TimelineEntry {
        lock.lock()
        defer { lock.unlock() }

        idCounter += 1
        let entry = TimelineEntry(
            id: "tl_\(idCounter)",
            timestamp: Date().timeIntervalSince1970 * 1000,
            category: category,
            action: action,
            summary: summary,
            duration: duration,
            source: source,
            data: data
        )

        buffer[head] = entry
        head = (head + 1) % capacity
        if count < capacity { count += 1 }

        return entry
    }

    public func get(since: Double? = nil, category: TimelineCategory? = nil, limit: Int = 100, search: String? = nil) -> (entries: [TimelineEntry], total: Int) {
        lock.lock()
        defer { lock.unlock() }

        var entries = getOrdered()

        if let since = since {
            entries = entries.filter { $0.timestamp >= since }
        }
        if let category = category {
            entries = entries.filter { $0.category == category }
        }
        if let search = search?.lowercased(), !search.isEmpty {
            entries = entries.filter { entry in
                entry.summary.lowercased().contains(search) ||
                    entry.action.lowercased().contains(search) ||
                    (entry.source?.file?.lowercased().contains(search) ?? false) ||
                    (entry.source?.component?.lowercased().contains(search) ?? false)
            }
        }

        let total = entries.count
        return (entries: Array(entries.suffix(limit)), total: total)
    }

    public func stats(windowMs: Int = 60_000) -> TimelineStats {
        lock.lock()
        defer { lock.unlock() }

        let now = Date().timeIntervalSince1970 * 1000
        let cutoff = now - Double(windowMs)
        let entries = getOrdered().filter { $0.timestamp >= cutoff }

        var rates: [String: Int] = [:]
        for entry in entries {
            rates[entry.category.rawValue, default: 0] += 1
        }

        return TimelineStats(totalEntries: count, windowMs: windowMs, rates: rates)
    }

    public func recent(limit: Int = 10) -> [TimelineEntry] {
        lock.lock()
        defer { lock.unlock() }
        return Array(getOrdered().suffix(limit))
    }

    private func getOrdered() -> [TimelineEntry] {
        if count < capacity {
            return buffer.prefix(count).compactMap { $0 }
        }
        let tail = buffer[head..<capacity].compactMap { $0 }
        let front = buffer[0..<head].compactMap { $0 }
        return tail + front
    }
}

#endif
