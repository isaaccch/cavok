import CavokKit
import Darwin
import Foundation
import Network
import NetworkExtension

@objc(GuardFilter)
final class GuardFilter: NEFilterDataProvider {
    private let cache = ProtectionCache()
    private var watch: RouteWatch?
    private var checkToken: Int32 = 0

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
        checkToken = CavokNotify.listen(PacketDropNote.check) { _ in
            CavokNotify.post(PacketDropNote.ready)
        }
        killIfPublicRouteLeft()
        notify_post_ready()
        completionHandler(nil)
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        watch?.stop()
        watch = nil
        let token = checkToken
        checkToken = 0
        if token != 0 { CavokNotify.cancel(token) }
        CavokNotify.post(PacketDropNote.blocked)
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        switch judge(flow, stage: .newFlow) {
        case .allowFinal:
            return .allow()
        case .allowWhileTunnel, .hold:
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
        switch judge(flow, stage: .outbound) {
        case .drop:
            return .drop()
        case .hold:
            let peek = readBytes.count < Int.max ? readBytes.count + 1 : readBytes.count
            return NEFilterDataVerdict(passBytes: 0, peekBytes: peek)
        case .allowFinal:
            return .allow()
        case .allowWhileTunnel:
            return NEFilterDataVerdict(passBytes: readBytes.count, peekBytes: 1)
        }
    }

    override func handleOutboundDataComplete(for flow: NEFilterFlow) -> NEFilterDataVerdict {
        switch judge(flow, stage: .outbound) {
        case .drop, .hold:
            return .drop()
        case .allowFinal, .allowWhileTunnel:
            return .allow()
        }
    }

    override func handleInboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict {
        .allow()
    }

    override func handleInboundDataComplete(for flow: NEFilterFlow) -> NEFilterDataVerdict {
        .allow()
    }

    private func judge(_ flow: NEFilterFlow, stage: FlowStage) -> FlowJudgment {
        guard let socket = flow as? NEFilterSocketFlow else { return .allowFinal }
        guard let pid = ProcessTable.pid(from: socket.sourceProcessAuditToken ?? socket.sourceAppAuditToken) else {
            return .allowFinal
        }
        switch PacketDrop.protection(pid: pid, snap: ProcessTable.snap, cache: cache) {
        case .unprotected:
            return .allowFinal
        case .unresolved:
            return .hold
        case .protected:
            guard let address = FlowRead.literal(socket) else {
                if stage == .outbound { return .drop }
                let route = RouteSocket.publicRoute()
                if route.interface == nil || route.physical { return .drop }
                return .hold
            }
            switch PacketDrop.verdict(protected: true, route: RouteSocket.kind(for: address)) {
            case .drop:
                return .drop
            case .allow:
                if PacketDrop.isLoopbackAddress(address) { return .allowFinal }
                return .allowWhileTunnel
            }
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

private enum FlowStage {
    case newFlow
    case outbound
}

private enum FlowJudgment {
    case allowFinal
    case allowWhileTunnel
    case hold
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
