import CavokSys
import Darwin
import Foundation

public enum RouteSocket {
    public static let publicDestination = RouteQuery.ipv4Destination

    public static func available() -> Bool {
        cavok_route_socket_ok()
    }

    /// Interface for one literal address. Nil when the socket is blocked or the address is not a literal.
    public static func interface(for address: String) -> String? {
        guard PacketDrop.isIPLiteral(address) else { return nil }
        var name = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        let code = address.withCString { cavok_route_interface($0, &name, Int32(name.count)) }
        guard code == 0 else { return nil }
        let text = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return text.isEmpty ? nil : text
    }

    /// Route kind for a destination. A missing literal uses the public address, the same lookup as `route -n get 1.1.1.1`.
    public static func kind(for address: String?) -> PacketDrop.RouteKind {
        if let address, PacketDrop.isLoopbackAddress(address) { return .loopback }
        let literal = address.flatMap { PacketDrop.isIPLiteral($0) ? $0 : nil } ?? publicDestination
        return PacketDrop.kind(interface: interface(for: literal))
    }
}

public enum ProcessTable {
    public static func snap(_ pid: Int32) -> ProcSnap? {
        var ppid: Int32 = 0
        var startSec: UInt64 = 0
        var startUsec: UInt64 = 0
        var command = [CChar](repeating: 0, count: 4096)
        guard cavok_proc_read(pid, &ppid, &startSec, &startUsec, &command, Int32(command.count)) == 0 else { return nil }
        return ProcSnap(
            pid: pid,
            ppid: ppid,
            startSec: startSec,
            startUsec: startUsec,
            command: String(decoding: command.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        )
    }

    public static func allSnaps() -> [Int32: ProcSnap] {
        let count = Int(cavok_proc_count())
        guard count > 0 else { return [:] }
        var pids = [Int32](repeating: 0, count: count)
        let got = Int(cavok_proc_pids(&pids, Int32(pids.count)))
        var snaps: [Int32: ProcSnap] = [:]
        for pid in pids.prefix(max(got, 0)) where pid > 1 {
            if let snap = snap(pid) { snaps[pid] = snap }
        }
        return snaps
    }

    /// Pids Guard should force-quit, including descendants. Pid 1 is never included.
    public static func protectedPids() -> [Int32] {
        let snaps = allSnaps()
        return snaps.keys.filter { PacketDrop.isProtected(pid: $0, snaps: snaps) }.sorted()
    }

    public static func pid(from token: Data?) -> Int32? {
        guard let token else { return nil }
        let value = token.withUnsafeBytes { raw in
            cavok_pid_from_audit_token(raw.baseAddress, Int32(raw.count))
        }
        return value > 1 ? value : nil
    }
}
