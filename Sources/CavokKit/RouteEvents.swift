import Darwin
import Dispatch
import Foundation

/// Wakes when the kernel posts a routing message other than an `RTM_GET` lookup.
/// The callback runs on a private queue. A lookup from that callback opens its own socket.
public final class RouteEvents: @unchecked Sendable {
    private let onEvent: @Sendable () -> Void
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?

    public init(onEvent: @escaping @Sendable () -> Void) {
        self.onEvent = onEvent
    }

    public func start() {
        lock.lock()
        defer { lock.unlock() }
        guard source == nil else { return }
        let opened = socket(PF_ROUTE, SOCK_RAW, 0)
        guard opened >= 0 else { return }
        let flags = fcntl(opened, F_GETFL)
        if flags >= 0 {
            _ = fcntl(opened, F_SETFL, flags | O_NONBLOCK)
        }
        fd = opened
        let source = DispatchSource.makeReadSource(fileDescriptor: opened, queue: DispatchQueue(label: "cavok.route-events"))
        source.setEventHandler { @Sendable [weak self] in
            self?.drain()
        }
        source.setCancelHandler {
            close(opened)
        }
        self.source = source
        source.resume()
    }

    public func stop() {
        lock.lock()
        let source = self.source
        self.source = nil
        fd = -1
        lock.unlock()
        source?.cancel()
    }

    private func drain() {
        lock.lock()
        let opened = fd
        lock.unlock()
        guard opened >= 0 else { return }
        var wake = false
        while true {
            var buffer = [UInt8](repeating: 0, count: 2048)
            let got = buffer.withUnsafeMutableBytes { raw -> ssize_t in
                guard let base = raw.baseAddress else { return -1 }
                return read(opened, base, raw.count)
            }
            if got < 0 {
                if errno == EINTR { continue }
                break
            }
            if got < 4 { break }
            // Byte 3 is rtm_type. 4 is RTM_GET, which our own lookup writes back onto this socket.
            if buffer[3] != 4 { wake = true }
        }
        if wake { onEvent() }
    }
}
