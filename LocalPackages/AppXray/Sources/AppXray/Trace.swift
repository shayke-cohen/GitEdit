import Foundation

#if DEBUG

/// Traces a synchronous function call, emitting fn.call/fn.return/fn.error to the timeline.
///
/// Usage:
///   let result = trace("calculateTotal") { items.reduce(0) { $0 + $1.price } }
@discardableResult
public func trace<T>(_ name: String, file: String = #file, line: Int = #line, _ body: () throws -> T) rethrows -> T {
    let source = TimelineSource(
        file: (file as NSString).lastPathComponent,
        line: line,
        function: name
    )
    AppXray.shared.timelineBridge.emit(
        category: .trace,
        action: "fn.call",
        summary: "\(name)()",
        source: source
    )
    let start = Date()
    do {
        let result = try body()
        let duration = Date().timeIntervalSince(start) * 1000
        AppXray.shared.timelineBridge.emit(
            category: .trace,
            action: "fn.return",
            summary: "\(name)() → \(String(format: "%.1f", duration))ms",
            duration: duration,
            source: source
        )
        return result
    } catch {
        AppXray.shared.timelineBridge.emit(
            category: .trace,
            action: "fn.error",
            summary: "\(name)() threw: \(error.localizedDescription)",
            source: source
        )
        throw error
    }
}

/// Traces an async function call, emitting fn.call/fn.return/fn.error to the timeline.
///
/// Usage:
///   let user = try await trace("fetchUser") { try await api.getUser(id) }
@discardableResult
public func trace<T>(_ name: String, file: String = #file, line: Int = #line, _ body: () async throws -> T) async rethrows -> T {
    let source = TimelineSource(
        file: (file as NSString).lastPathComponent,
        line: line,
        function: name
    )
    AppXray.shared.timelineBridge.emit(
        category: .trace,
        action: "fn.call",
        summary: "\(name)()",
        source: source
    )
    let start = Date()
    do {
        let result = try await body()
        let duration = Date().timeIntervalSince(start) * 1000
        AppXray.shared.timelineBridge.emit(
            category: .trace,
            action: "fn.return",
            summary: "\(name)() → \(String(format: "%.1f", duration))ms",
            duration: duration,
            source: source
        )
        return result
    } catch {
        AppXray.shared.timelineBridge.emit(
            category: .trace,
            action: "fn.error",
            summary: "\(name)() threw: \(error.localizedDescription)",
            source: source
        )
        throw error
    }
}

#endif
