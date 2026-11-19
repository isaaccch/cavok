import Foundation

public struct SessionFacts: Equatable, Sendable {
    public struct IPv6Sighting: Equatable, Sendable {
        public var host: String
        public var loc: String?
        public var ipv4Loc: String?

        public init(host: String, loc: String?, ipv4Loc: String?) {
            self.host = host
            self.loc = loc
            self.ipv4Loc = ipv4Loc
        }
    }

    public var routeIsPhysical: Bool
    public var routeIsTunnel: Bool
    public var routeInterface: String?
    public var claudeIP: String?
    public var claudeLoc: String?
    public var chatgptIP: String?
    public var chatgptLoc: String?
    public var pinnedIP: String?
    public var socketLeak: Bool
    public var shellLeftover: Bool
    public var launchctlLeftover: Bool
    public var claudeConfigLeftover: Bool
    public var codexLeftover: Bool
    public var proxyLeftover: Bool
    public var ipv6RouteIsPhysical: Bool
    public var ipv6RouteInterface: String?
    public var ipv6Hosts: [IPv6Sighting]

    public init(
        routeIsPhysical: Bool = false,
        routeIsTunnel: Bool = false,
        routeInterface: String? = nil,
        claudeIP: String? = nil,
        claudeLoc: String? = nil,
        chatgptIP: String? = nil,
        chatgptLoc: String? = nil,
        pinnedIP: String? = nil,
        socketLeak: Bool = false,
        shellLeftover: Bool = false,
        launchctlLeftover: Bool = false,
        claudeConfigLeftover: Bool = false,
        codexLeftover: Bool = false,
        proxyLeftover: Bool = false,
        ipv6RouteIsPhysical: Bool = false,
        ipv6RouteInterface: String? = nil,
        ipv6Hosts: [IPv6Sighting] = []
    ) {
        self.routeIsPhysical = routeIsPhysical
        self.routeIsTunnel = routeIsTunnel
        self.routeInterface = routeInterface
        self.claudeIP = claudeIP
        self.claudeLoc = claudeLoc
        self.chatgptIP = chatgptIP
        self.chatgptLoc = chatgptLoc
        self.pinnedIP = pinnedIP
        self.socketLeak = socketLeak
        self.shellLeftover = shellLeftover
        self.launchctlLeftover = launchctlLeftover
        self.claudeConfigLeftover = claudeConfigLeftover
        self.codexLeftover = codexLeftover
        self.proxyLeftover = proxyLeftover
        self.ipv6RouteIsPhysical = ipv6RouteIsPhysical
        self.ipv6RouteInterface = ipv6RouteInterface
        self.ipv6Hosts = ipv6Hosts
    }
}

/// One pair of IPv4 exits. A nil field means that host did not answer.
public struct ExitReading: Equatable, Sendable {
    public var claudeIP: String?
    public var claudeLoc: String?
    public var chatgptIP: String?
    public var chatgptLoc: String?

    public init(
        claudeIP: String? = nil,
        claudeLoc: String? = nil,
        chatgptIP: String? = nil,
        chatgptLoc: String? = nil
    ) {
        self.claudeIP = claudeIP
        self.claudeLoc = claudeLoc
        self.chatgptIP = chatgptIP
        self.chatgptLoc = chatgptLoc
    }
}

public enum ExitDrift {
    /// True when a host that answered differs from the last reading.
    /// A host that did not answer is not a change. An answer after a miss is.
    public static func changed(from previous: ExitReading, to next: ExitReading) -> Bool {
        hostChanged(previous.claudeIP, previous.claudeLoc, next.claudeIP, next.claudeLoc)
            || hostChanged(previous.chatgptIP, previous.chatgptLoc, next.chatgptIP, next.chatgptLoc)
    }

    private static func hostChanged(
        _ previousIP: String?,
        _ previousLoc: String?,
        _ nextIP: String?,
        _ nextLoc: String?
    ) -> Bool {
        guard let nextIP else { return false }
        guard let previousIP else { return true }
        if previousIP != nextIP { return true }
        guard let nextLoc else { return false }
        guard let previousLoc else { return true }
        return previousLoc.uppercased() != nextLoc.uppercased()
    }
}

public enum SessionGate {
    /// Why Guard should quit, or nil when this reading is not a block.
    /// A missing trace, a time zone, a curl challenge, and DNS are not reasons.
    public static func blockingReason(_ facts: SessionFacts) -> String? {
        if facts.routeIsPhysical {
            let name = facts.routeInterface ?? "Wi-Fi"
            return "The IPv4 route is \(name), not the tunnel."
        }
        if let loc = facts.claudeLoc, facts.claudeIP != nil, !RegionGate.allows(loc) {
            return "Claude's exit is \(loc)."
        }
        if let loc = facts.chatgptLoc, facts.chatgptIP != nil, !RegionGate.allows(loc) {
            return "ChatGPT's exit is \(loc)."
        }
        if let pinned = facts.pinnedIP {
            if let ip = facts.claudeIP, ip != pinned {
                return "Claude's exit \(ip) is not the pinned IP \(pinned)."
            }
            if let ip = facts.chatgptIP, ip != pinned {
                return "ChatGPT's exit \(ip) is not the pinned IP \(pinned)."
            }
        }
        if let claudeIP = facts.claudeIP, let chatgptIP = facts.chatgptIP, claudeIP != chatgptIP {
            return "Claude's exit is \(claudeIP) and ChatGPT's exit is \(chatgptIP)."
        }
        if facts.shellLeftover {
            return "A shell startup file still sets a proxy or custom API address."
        }
        if facts.launchctlLeftover {
            return "The login environment still sets a proxy or custom API address."
        }
        if facts.claudeConfigLeftover {
            return "A Claude config still has a relay or proxy."
        }
        if facts.codexLeftover {
            return "The Codex config still has a custom API address."
        }
        if facts.proxyLeftover {
            return "A system proxy is still on."
        }
        if facts.ipv6RouteIsPhysical {
            let name = facts.ipv6RouteInterface ?? "Wi-Fi"
            return "The IPv6 route is \(name)."
        }
        if let host = facts.ipv6Hosts.first(where: ipv6Leak) {
            let loc = host.loc ?? "an unknown country"
            return "\(host.host) sees IPv6 in \(loc)."
        }
        return nil
    }

    /// Both open buttons. A missing exit stays off. A challenge, time zone, or DNS warning does not.
    public static func canOpen(_ facts: SessionFacts) -> Bool {
        guard blockingReason(facts) == nil else { return false }
        guard facts.routeIsTunnel, !facts.socketLeak else { return false }
        guard let claudeIP = facts.claudeIP, let claudeLoc = facts.claudeLoc, RegionGate.allows(claudeLoc) else { return false }
        guard let chatgptIP = facts.chatgptIP, let chatgptLoc = facts.chatgptLoc, RegionGate.allows(chatgptLoc) else { return false }
        guard claudeIP == chatgptIP, claudeLoc.uppercased() == chatgptLoc.uppercased() else { return false }
        return true
    }

    private static func ipv6Leak(_ host: SessionFacts.IPv6Sighting) -> Bool {
        if let loc = host.loc, RegionGate.blocked.contains(loc.uppercased()) { return true }
        if let ipv4 = host.ipv4Loc, !ipv4.isEmpty, host.loc?.uppercased() != ipv4.uppercased() { return true }
        return false
    }
}
