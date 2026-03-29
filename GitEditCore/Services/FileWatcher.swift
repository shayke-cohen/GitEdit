import Foundation

/// Watches a directory for file system changes using FSEvents.
/// Notifies observers when files are created, modified, or deleted.
public final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let path: String
    private let callback: ([String]) -> Void

    public init(path: String, callback: @escaping ([String]) -> Void) {
        self.path = path
        self.callback = callback
    }

    deinit {
        stop()
    }

    public func start() {
        let pathCF = path as CFString
        var context = FSEventStreamContext()
        context.info = Unmanaged.passRetained(CallbackWrapper(callback)).toOpaque()

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
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
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
