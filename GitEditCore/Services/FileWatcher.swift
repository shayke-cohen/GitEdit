import Foundation

/// Watches a directory for file system changes using FSEvents.
/// Notifies observers when files are created, modified, or deleted.
public final class FileWatcher {
    private var stream: FSEventStreamRef?
    private var contextInfo: UnsafeMutableRawPointer?
    private let path: String
    private let callback: ([String]) -> Void
    private let queue = DispatchQueue(label: "com.gitedit.filewatcher", qos: .utility)

    public init(path: String, callback: @escaping ([String]) -> Void) {
        self.path = path
        self.callback = callback
    }

    deinit {
        stop()
    }

    public func start() {
        // Stop any existing stream to prevent leaking the previous contextInfo
        if stream != nil { stop() }

        let pathCF = path as CFString
        let opaquePtr = Unmanaged.passRetained(CallbackWrapper(callback)).toOpaque()
        self.contextInfo = opaquePtr

        var context = FSEventStreamContext()
        context.info = opaquePtr

        guard let stream = FSEventStreamCreate(
            nil,
            fsEventCallback,
            &context,
            [pathCF] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,  // 300ms latency — fast enough for gutter updates
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil

        // Balance the passRetained from start() to avoid memory leak
        if let info = contextInfo {
            Unmanaged<CallbackWrapper>.fromOpaque(info).release()
            contextInfo = nil
        }
    }
}

// MARK: - FSEvents C callback bridge

private final class CallbackWrapper {
    let callback: ([String]) -> Void
    init(_ callback: @escaping ([String]) -> Void) {
        self.callback = callback
    }
}

private func fsEventCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let wrapper = Unmanaged<CallbackWrapper>.fromOpaque(info).takeUnretainedValue()

    guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
    wrapper.callback(paths)
}
