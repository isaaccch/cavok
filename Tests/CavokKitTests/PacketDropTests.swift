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
        32: snap(32, 1, "/usr/local/bin/node\u{1F}--max-old-space-size\u{1F}4096\u{1F}/Users/me/Library/Application Support/@anthropic-ai/claude-code/cli.js"),
        33: snap(33, 1, "vim\u{1F}claude\u{1F}file"),
        34: snap(34, 1, "bun\u{1F}/Users/me/.local/share/claude/cli.js"),
        35: snap(35, 1, "npx\u{1F}/pkg/@anthropic-ai/claude-code/cli.js"),
        36: snap(36, 1, "/Users/me/Library/Application Support/claude\u{1F}"),
        37: snap(37, 1, "npx cowsay claude"),
        40: snap(40, 1, "/usr/sbin/mDNSResponder"),
        50: snap(50, 1, "/opt/codex-aarch64-apple-darwin"),
        51: snap(51, 50, "/usr/bin/python3 -m tool"),
        52: snap(52, 1, "/opt/codex-x86_64-apple-darwin"),
    ]
    #expect(PacketDrop.isProtected(pid: 10, snaps: snaps))
    #expect(PacketDrop.isProtected(pid: 12, snaps: snaps))
    #expect(PacketDrop.isProtected(pid: 13, snaps: snaps))
    #expect(!PacketDrop.isProtected(pid: 1, snaps: snaps))
    #expect(!PacketDrop.isProtected(pid: 20, snaps: snaps))
    #expect(!PacketDrop.isProtected(pid: 21, snaps: snaps))
    #expect(PacketDrop.isProtected(pid: 30, snaps: snaps))
    #expect(!PacketDrop.isProtected(pid: 31, snaps: snaps))
    #expect(PacketDrop.isProtected(pid: 32, snaps: snaps))
    #expect(!PacketDrop.isProtected(pid: 33, snaps: snaps))
    #expect(PacketDrop.isProtected(pid: 34, snaps: snaps))
    #expect(PacketDrop.isProtected(pid: 35, snaps: snaps))
    #expect(PacketDrop.isProtected(pid: 36, snaps: snaps))
    #expect(!PacketDrop.isProtected(pid: 37, snaps: snaps))
    #expect(!PacketDrop.isProtected(pid: 40, snaps: snaps))
    #expect(PacketDrop.isProtected(pid: 51, snaps: snaps))
    #expect(PacketDrop.isProtected(pid: 52, snaps: snaps))
    let cache = ProtectionCache()
    let lookup: (Int32) -> ProcSnap? = { snaps[$0] }
    #expect(PacketDrop.protection(pid: 13, snap: lookup, cache: cache) == .protected)
    #expect(PacketDrop.protection(pid: 12, snap: lookup, cache: cache) == .protected)
    #expect(PacketDrop.protection(pid: 20, snap: lookup, cache: cache) == .unprotected)
    #expect(PacketDrop.protection(pid: 21, snap: lookup, cache: cache) == .unprotected)
    #expect(PacketDrop.protection(pid: 31, snap: lookup, cache: cache) == .unprotected)
    #expect(PacketDrop.protection(pid: 40, snap: lookup, cache: cache) == .unprotected)
    #expect(PacketDrop.protection(pid: 51, snap: lookup, cache: cache) == .protected)
    #expect(PacketDrop.protection(pid: 1, snap: lookup, cache: cache) == .unprotected)
}

@Test func anUnreadAncestorIsNotCached() {
    let cache = ProtectionCache()
    var snaps: [Int32: ProcSnap] = [
        12: snap(12, 11, "/usr/bin/curl"),
        10: snap(10, 1, "/usr/local/bin/claude"),
    ]
    let lookup: (Int32) -> ProcSnap? = { snaps[$0] }
    #expect(PacketDrop.protection(pid: 12, snap: lookup, cache: cache) == .unresolved)
    snaps[11] = snap(11, 10, "/bin/zsh")
    #expect(PacketDrop.protection(pid: 12, snap: lookup, cache: cache) == .protected)
}

@Test func aProtectedStartTimeDoesNotCoverTheNextProcess() {
    let cache = ProtectionCache()
    let claude = snap(7, 1, "/usr/local/bin/claude", start: 1)
    let reused = snap(7, 1, "vim claude", start: 9)
    #expect(PacketDrop.protection(pid: 7, snap: { $0 == 7 ? claude : nil }, cache: cache) == .protected)
    #expect(PacketDrop.protection(pid: 7, snap: { $0 == 7 ? reused : nil }, cache: cache) == .unprotected)
    #expect(PacketDrop.protection(pid: 7, snap: { $0 == 7 ? claude : nil }, cache: cache) == .protected)
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

@Test func routeLookupStillWorksWhileListening() throws {
    guard RouteSocket.available() else { return }
    let events = RouteEvents { }
    events.start()
    defer { events.stop() }
    let got = try #require(RouteSocket.interface(for: "1.1.1.1"))
    #expect(!got.isEmpty)
    #expect(RouteSocket.publicRoute().interface == got)
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
