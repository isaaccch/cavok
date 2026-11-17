import Darwin
import Foundation

public struct ProcSnap: Equatable, Sendable {
    public var pid: Int32
    public var ppid: Int32
    public var startSec: UInt64
    public var startUsec: UInt64
    public var command: String

    public init(pid: Int32, ppid: Int32, startSec: UInt64, startUsec: UInt64, command: String) {
        self.pid = pid
        self.ppid = ppid
        self.startSec = startSec
        self.startUsec = startUsec
        self.command = command
    }
}

public enum PacketDropNote {
    public static let ready = "com.isaaccheung.cavok.packet-drop-ready"
    public static let blocked = "com.isaaccheung.cavok.packet-drop-blocked"
    public static let check = "com.isaaccheung.cavok.packet-drop-check"
}

public enum ProtectionState: Equatable, Sendable {
    case protected
    case unprotected
    case unresolved
}

public enum PacketDrop {
    public enum Verdict: Equatable, Sendable {
        case allow
        case drop
    }

    /// What the in-process route lookup said about one destination.
    public enum RouteKind: Equatable, Sendable {
        case tunnel
        case loopback
        case physical
        case unknown
    }

    public static func kind(interface: String?) -> RouteKind {
        guard let interface else { return .unknown }
        let trimmed = interface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown }
        let lower = trimmed.lowercased()
        if lower == "lo" || lower.hasPrefix("lo") { return .loopback }
        if RouteParse.isTunnel(trimmed) { return .tunnel }
        if RouteParse.isPhysical(trimmed, hardware: []) { return .physical }
        return .unknown
    }

    public static func isLoopbackAddress(_ address: String) -> Bool {
        let host = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host == "::1" || host == "0:0:0:0:0:0:0:1" { return true }
        return host.hasPrefix("127.")
    }

    public static func isIPLiteral(_ address: String) -> Bool {
        let host = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty || host.contains("%") { return false }
        if isLoopbackAddress(host) { return true }
        var v4 = in_addr()
        if host.withCString({ inet_pton(AF_INET, $0, &v4) }) == 1 { return true }
        var v6 = in6_addr()
        return host.withCString({ inet_pton(AF_INET6, $0, &v6) }) == 1
    }

    /// A protected socket is dropped unless this destination is the tunnel or loopback.
    /// A tunnel allow is provisional: call `stillAllowed` again when the route changes.
    public static func verdict(protected: Bool, route: RouteKind) -> Verdict {
        guard protected else { return .allow }
        switch route {
        case .tunnel, .loopback: return .allow
        case .physical, .unknown: return .drop
        }
    }

    public static func stillAllowed(_ route: RouteKind) -> Verdict {
        switch route {
        case .tunnel, .loopback: return .allow
        case .physical, .unknown: return .drop
        }
    }

    /// This pid, or an ancestor before pid 1, matches Guard's process list.
    /// An ancestor is not protected merely because a child matched.
    public static func isProtected(pid: Int32, snaps: [Int32: ProcSnap]) -> Bool {
        var current = pid
        var seen = Set<Int32>()
        while current > 1, seen.insert(current).inserted, let snap = snaps[current] {
            if ProcessMatch.matches(snap.command) { return true }
            current = snap.ppid
        }
        return false
    }

    /// One pid and its parents, without a full process table.
    /// A hop that cannot be read is unresolved and is not cached.
    /// A walk that reaches pid 1 is unprotected and is not cached.
    /// Only a protected hit is stored, keyed by pid and start time.
    public static func protection(
        pid: Int32,
        snap: (Int32) -> ProcSnap?,
        cache: ProtectionCache
    ) -> ProtectionState {
        var current = pid
        var seen = Set<Int32>()
        var chain: [(pid: Int32, startSec: UInt64, startUsec: UInt64)] = []
        while current > 1, seen.insert(current).inserted {
            guard let info = snap(current) else { return .unresolved }
            chain.append((info.pid, info.startSec, info.startUsec))
            if cache.protectedHit(pid: info.pid, startSec: info.startSec, startUsec: info.startUsec)
                || ProcessMatch.matches(info.command) {
                cache.storeProtected(chain)
                return .protected
            }
            current = info.ppid
        }
        return .unprotected
    }
}

public struct ProtectedStamp: Equatable, Sendable {
    public var pid: Int32
    public var startSec: UInt64
    public var startUsec: UInt64
    public var protected: Bool

    public init(pid: Int32, startSec: UInt64, startUsec: UInt64, protected: Bool) {
        self.pid = pid
        self.startSec = startSec
        self.startUsec = startUsec
        self.protected = protected
    }
}

/// Remembers a pid only for the start time it was read with. A reused pid is judged again.
public final class ProtectionCache: @unchecked Sendable {
    private let lock = NSLock()
    private var byPid: [Int32: ProtectedStamp] = [:]

    public init() {}

    public func isProtected(pid: Int32, snaps: [Int32: ProcSnap]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let snap = snaps[pid] else { return false }
        if let hit = byPid[pid], hit.startSec == snap.startSec, hit.startUsec == snap.startUsec {
            return hit.protected
        }
        let answer = PacketDrop.isProtected(pid: pid, snaps: snaps)
        byPid[pid] = ProtectedStamp(pid: pid, startSec: snap.startSec, startUsec: snap.startUsec, protected: answer)
        return answer
    }

    func protectedHit(pid: Int32, startSec: UInt64, startUsec: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let hit = byPid[pid], hit.protected else { return false }
        return hit.startSec == startSec && hit.startUsec == startUsec
    }

    func storeProtected(_ chain: [(pid: Int32, startSec: UInt64, startUsec: UInt64)]) {
        lock.lock()
        defer { lock.unlock() }
        for item in chain {
            byPid[item.pid] = ProtectedStamp(
                pid: item.pid,
                startSec: item.startSec,
                startUsec: item.startUsec,
                protected: true
            )
        }
    }
}
