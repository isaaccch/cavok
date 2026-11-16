import Foundation
import Testing
@testable import CavokKit

private func snap(_ pid: Int32, _ ppid: Int32, _ command: String, start: UInt64 = 1) -> ProcSnap {
    ProcSnap(pid: pid, ppid: ppid, startSec: start, startUsec: 0, command: command)
}

@Test func routeKindFollowsTheInterfaceName() {
    #expect(PacketDrop.kind(interface: "utun4") == .tunnel)
    #expect(PacketDrop.kind(interface: "en0") == .physical)
    #expect(PacketDrop.kind(interface: "bridge0") == .physical)
    #expect(PacketDrop.kind(interface: "lo0") == .loopback)
    #expect(PacketDrop.kind(interface: nil) == .unknown)
    #expect(PacketDrop.kind(interface: "  ") == .unknown)
    #expect(PacketDrop.kind(interface: "gif0") == .unknown)
    #expect(PacketDrop.isLoopbackAddress("127.0.0.1"))
    #expect(PacketDrop.isLoopbackAddress("::1"))
    #expect(!PacketDrop.isLoopbackAddress("1.1.1.1"))
    #expect(PacketDrop.isIPLiteral("1.1.1.1"))
    #expect(PacketDrop.isIPLiteral("2001:db8::1"))
    #expect(!PacketDrop.isIPLiteral("claude.ai"))
}

@Test func protectedSocketFollowsTheRoute() {
    #expect(PacketDrop.verdict(protected: true, route: .tunnel) == .allow)
    #expect(PacketDrop.verdict(protected: true, route: .loopback) == .allow)
    #expect(PacketDrop.verdict(protected: true, route: .physical) == .drop)
    #expect(PacketDrop.verdict(protected: true, route: .unknown) == .drop)
    #expect(PacketDrop.verdict(protected: false, route: .physical) == .allow)
    #expect(PacketDrop.stillAllowed(.tunnel) == .allow)
    #expect(PacketDrop.stillAllowed(.physical) == .drop)
    #expect(PacketDrop.stillAllowed(.unknown) == .drop)
}

@Test func descendantsOfClaudeAreProtected() {
    let snaps: [Int32: ProcSnap] = [
        10: snap(10, 1, "/usr/local/bin/claude"),
        11: snap(11, 10, "/bin/zsh -lc curl"),
        12: snap(12, 11, "/usr/bin/curl https://example.com"),
        13: snap(13, 12, "/usr/bin/git fetch"),
        20: snap(20, 1, "vim claude"),
        21: snap(21, 1, "/usr/bin/grep claude file"),
        30: snap(30, 1, "/usr/local/bin/node /pkg/@anthropic-ai/claude-code/cli.js"),
        31: snap(31, 1, "/usr/local/bin/node /pkg/other.js"),
        40: snap(40, 1, "/usr/sbin/mDNSResponder"),
        50: snap(50, 1, "/opt/codex-aarch64-apple-darwin"),
        51: snap(51, 50, "/usr/bin/python3 -m tool"),
    ]
    #expect(PacketDrop.isProtected(pid: 10, snaps: snaps))
    #expect(PacketDrop.isProtected(pid: 12, snaps: snaps))
    #expect(PacketDrop.isProtected(pid: 13, snaps: snaps))
    #expect(!PacketDrop.isProtected(pid: 1, snaps: snaps))
    #expect(!PacketDrop.isProtected(pid: 20, snaps: snaps))
    #expect(!PacketDrop.isProtected(pid: 21, snaps: snaps))
    #expect(PacketDrop.isProtected(pid: 30, snaps: snaps))
    #expect(!PacketDrop.isProtected(pid: 31, snaps: snaps))
    #expect(!PacketDrop.isProtected(pid: 40, snaps: snaps))
    #expect(PacketDrop.isProtected(pid: 51, snaps: snaps))
}

@Test func aReusedPidDoesNotKeepTheOldRule() {
    let cache = ProtectionCache()
    let first: [Int32: ProcSnap] = [7: snap(7, 1, "/usr/local/bin/claude", start: 1)]
    #expect(cache.isProtected(pid: 7, snaps: first))
    let reused: [Int32: ProcSnap] = [7: snap(7, 1, "vim claude", start: 9)]
    #expect(!cache.isProtected(pid: 7, snaps: reused))
    let again: [Int32: ProcSnap] = [7: snap(7, 1, "/usr/local/bin/claude", start: 1)]
    #expect(cache.isProtected(pid: 7, snaps: again))
}

@Test func inProcessRouteMatchesRouteCommand() throws {
    guard RouteSocket.available() else { return }
    let got = try #require(RouteSocket.interface(for: "1.1.1.1"))
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/sbin/route")
    process.arguments = ["-n", "get", "1.1.1.1"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    #expect(RouteParse.interfaceName(in: text) == got)
}
