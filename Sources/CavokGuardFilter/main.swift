import CavokKit
import Darwin
import Foundation
import Network
import NetworkExtension

@objc(GuardFilter)
final class GuardFilter: NEFilterDataProvider {
    private let cache = ProtectionCache()
    private var watch: RouteWatch?

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        guard RouteSocket.available() else {
            PacketDropNote.blocked.withCString { _ in
                CavokNotify.post(PacketDropNote.blocked)
            }
            completionHandler(RouteSocketBlocked())
            return
        }
        let watch = RouteWatch { [weak self] in
            self?.killIfPublicRouteLeft()
        }
        watch.start()
        self.watch = watch
        killIfPublicRouteLeft()
        notify_post_ready()
        completionHandler(nil)
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        watch?.stop()
        watch = nil
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        switch judge(flow) {
        case .allowFinal:
            return .allow()
        case .allowWhileTunnel:
            return NEFilterNewFlowVerdict.filterDataVerdict(
                withFilterInbound: false,
                peekInboundBytes: 0,
                filterOutbound: true,
                peekOutboundBytes: 1
            )
        case .drop:
            return .drop()
        }
    }

    override func handleOutboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict {
        if judge(flow) == .drop {
            return .drop()
        }
        let pass = readBytes.count
        return NEFilterDataVerdict(passBytes: pass, peekBytes: 1)
    }

    override func handleOutboundDataComplete(for flow: NEFilterFlow) -> NEFilterDataVerdict {
        judge(flow) == .drop ? .drop() : .allow()
    }

    override func handleInboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict {
        .allow()
    }

    override func handleInboundDataComplete(for flow: NEFilterFlow) -> NEFilterDataVerdict {
        .allow()
    }

    private func judge(_ flow: NEFilterFlow) -> FlowJudgment {
        guard let socket = flow as? NEFilterSocketFlow else { return .allowFinal }
        guard let pid = ProcessTable.pid(from: socket.sourceProcessAuditToken ?? socket.sourceAppAuditToken) else {
            return .allowFinal
        }
        let snaps = ProcessTable.allSnaps()
        guard cache.isProtected(pid: pid, snaps: snaps) else { return .allowFinal }
        let address = FlowRead.literal(socket)
        switch PacketDrop.verdict(protected: true, route: RouteSocket.kind(for: address)) {
        case .drop:
            return .drop
        case .allow:
            if address.map(PacketDrop.isLoopbackAddress) == true { return .allowFinal }
            return .allowWhileTunnel
        }
    }

    private func killIfPublicRouteLeft() {
        guard PacketDrop.stillAllowed(RouteSocket.kind(for: nil)) == .drop else { return }
        let selfPid = getpid()
        for pid in ProcessTable.protectedPids() where pid != selfPid {
            kill(pid, SIGKILL)
        }
    }
}

private enum FlowJudgment {
    case allowFinal
    case allowWhileTunnel
    case drop
}

private struct RouteSocketBlocked: Error {}

enum FlowRead {
    static func literal(_ socket: NEFilterSocketFlow) -> String? {
        if let host = socket.remoteHostname {
            let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
            if PacketDrop.isIPLiteral(trimmed) { return trimmed }
        }
        return address(socket.remoteFlowEndpoint)
    }

    private static func address(_ endpoint: NWEndpoint?) -> String? {
        guard let endpoint else { return nil }
        switch endpoint {
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let address):
                return "\(address)"
            case .ipv6(let address):
                let text = "\(address)"
                if let zone = text.firstIndex(of: "%") { return String(text[..<zone]) }
                return text
            default:
                return nil
            }
        default:
            return nil
        }
    }
}

private func notify_post_ready() {
    CavokNotify.post(PacketDropNote.ready)
}

private final class RouteWatch: @unchecked Sendable {
    private let onChange: () -> Void
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func start() {
        let fd = socket(PF_ROUTE, SOCK_RAW, 0)
        guard fd >= 0 else { return }
        self.fd = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "cavok.route-watch"))
        source.setEventHandler { [weak self] in
            guard let self, self.fd >= 0 else { return }
            var buffer = [UInt8](repeating: 0, count: 2048)
            let got = read(self.fd, &buffer, buffer.count)
            guard got >= 4 else { return }
            if buffer[3] == 4 { return }
            self.onChange()
        }
        source.setCancelHandler {
            close(fd)
        }
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        fd = -1
    }
}

NEProvider.startSystemExtensionMode()
_ = GuardFilter.self
dispatchMain()
