import Foundation
import Testing
@testable import CavokKit

private func sharedExit() -> SessionFacts {
    SessionFacts(
        routeIsTunnel: true,
        routeInterface: "utun4",
        claudeIP: "93.118.41.99",
        claudeLoc: "JP",
        chatgptIP: "93.118.41.99",
        chatgptLoc: "JP",
        ipv6RouteInterface: "utun4"
    )
}

@Test func sessionGatePinMismatchOnEitherExit() {
    var claude = sharedExit()
    claude.pinnedIP = "1.1.1.1"
    claude.claudeIP = "2.2.2.2"
    #expect(SessionGate.blockingReason(claude) != nil)
    #expect(!SessionGate.canOpen(claude))

    var chatgpt = sharedExit()
    chatgpt.pinnedIP = "1.1.1.1"
    chatgpt.chatgptIP = "8.8.8.8"
    #expect(SessionGate.blockingReason(chatgpt) != nil)
    #expect(!SessionGate.canOpen(chatgpt))
}

@Test func sessionGateExitsDisagreeAndMissingChatGPTStaysClosed() {
    var split = sharedExit()
    split.chatgptIP = "8.8.8.8"
    split.chatgptLoc = "US"
    #expect(SessionGate.blockingReason(split) != nil)
    #expect(!SessionGate.canOpen(split))

    var missing = sharedExit()
    missing.chatgptIP = nil
    missing.chatgptLoc = nil
    #expect(SessionGate.blockingReason(missing) == nil)
    #expect(!SessionGate.canOpen(missing))
}

@Test func sessionGateConfigLeftoverBlocksOpen() {
    var facts = sharedExit()
    facts.claudeConfigLeftover = true
    #expect(SessionGate.blockingReason(facts) == "A Claude config still has a relay or proxy.")
    #expect(!SessionGate.canOpen(facts))
}

@Test func sessionGateRealIPv6LeakBlocksOpen() {
    var facts = sharedExit()
    facts.ipv6Hosts = [
        SessionFacts.IPv6Sighting(host: "chatgpt.com", loc: "HK", ipv4Loc: "JP"),
    ]
    #expect(SessionGate.blockingReason(facts) == "chatgpt.com sees IPv6 in HK.")
    #expect(!SessionGate.canOpen(facts))

    var otherCountry = sharedExit()
    otherCountry.ipv6Hosts = [
        SessionFacts.IPv6Sighting(host: "claude.ai", loc: "US", ipv4Loc: "JP"),
    ]
    #expect(SessionGate.blockingReason(otherCountry) != nil)
    #expect(!SessionGate.canOpen(otherCountry))
}

private func japanExit() -> ExitReading {
    ExitReading(claudeIP: "93.118.41.99", claudeLoc: "JP", chatgptIP: "93.118.41.99", chatgptLoc: "JP")
}

@Test func exitDriftSameReadingIsNotAChange() {
    let seen = japanExit()
    #expect(!ExitDrift.changed(from: seen, to: seen))
    var lower = seen
    lower.claudeLoc = "jp"
    lower.chatgptLoc = "jp"
    #expect(!ExitDrift.changed(from: seen, to: lower))
}

@Test func exitDriftNewAddressOrCountryIsAChange() {
    var newClaude = japanExit()
    newClaude.claudeIP = "1.1.1.1"
    #expect(ExitDrift.changed(from: japanExit(), to: newClaude))

    var newCountry = japanExit()
    newCountry.chatgptLoc = "US"
    #expect(ExitDrift.changed(from: japanExit(), to: newCountry))
}

@Test func exitDriftTimeoutIsNotAChange() {
    var timedOut = japanExit()
    timedOut.claudeIP = nil
    timedOut.claudeLoc = nil
    #expect(!ExitDrift.changed(from: japanExit(), to: timedOut))

    #expect(!ExitDrift.changed(from: japanExit(), to: ExitReading()))
}

@Test func exitDriftAnswerAfterAMissIsAChange() {
    #expect(ExitDrift.changed(from: ExitReading(), to: japanExit()))

    let onlyClaude = ExitReading(claudeIP: "93.118.41.99", claudeLoc: "JP")
    var withChatGPT = onlyClaude
    withChatGPT.chatgptIP = "93.118.41.99"
    withChatGPT.chatgptLoc = "JP"
    #expect(ExitDrift.changed(from: onlyClaude, to: withChatGPT))
}

@Test func sessionGateBothExitsAllowedWithNoPinCanOpen() {
    let facts = sharedExit()
    #expect(SessionGate.blockingReason(facts) == nil)
    #expect(SessionGate.canOpen(facts))
}

@Test func ipv6RejectsIPv4AndMappedAddressesOnEitherHost() {
    let v4 = "ip=93.118.41.99\nloc=JP\n"
    let mapped = "ip=::ffff:93.118.41.99\nloc=JP\n"
    let upper = "ip=::FFFF:192.0.2.1\nloc=HK\n"
    let real = "ip=2001:db8::1\nloc=JP\n"
    #expect(IPv6Trace.result(host: "claude.ai", trace: v4).ip == nil)
    #expect(IPv6Trace.result(host: "chatgpt.com", trace: v4).ip == nil)
    #expect(IPv6Trace.result(host: "claude.ai", trace: mapped).ip == nil)
    #expect(IPv6Trace.result(host: "chatgpt.com", trace: mapped).loc == nil)
    #expect(IPv6Trace.result(host: "chatgpt.com", trace: upper).ip == nil)
    let kept = IPv6Trace.result(host: "claude.ai", trace: real)
    #expect(kept.ip == "2001:db8::1")
    #expect(kept.loc == "JP")
    #expect(IPv6Trace.result(host: "chatgpt.com", trace: real).ip == "2001:db8::1")
}

@Test func backupIsWriteOnce() {
    #expect(BackupFile.shouldCreate(backupExists: false))
    #expect(!BackupFile.shouldCreate(backupExists: true))
}

@Test func reachabilityChallengeOnOneHostBeside200() {
    let challenged = "HTTP/2 403\r\ncf-mitigated: challenge\r\n"
    let ok = "HTTP/2 200\r\ncontent-type: text/html\r\n"
    #expect(ReachParse.challengedHosts(claude: challenged, chatgpt: ok) == ["claude.ai"])
    #expect(ReachParse.challengedHosts(claude: ok, chatgpt: "HTTP/2 421\r\n") == ["chatgpt.com"])
    #expect(ReachParse.parse("HTTP/2 200\r\ncf-mitigated: challenge\r\n").challenged)
    #expect(!ReachParse.parse(ok).challenged)
}

@Test func localeTagsAndDNSInterfaces() {
    #expect(LocaleTags.find(locale: "en_HK", languages: [], inputSources: "").map(\.region) == ["HK"])
    #expect(LocaleTags.find(locale: "en_US", languages: ["yue-Hant-HK"], inputSources: "").map(\.region) == ["HK"])
    #expect(LocaleTags.find(locale: "en_US", languages: ["zh-Hans-HK"], inputSources: "").map(\.region) == ["HK"])
    #expect(LocaleTags.find(locale: "en_US", languages: ["zh-Hant-HK"], inputSources: "").map(\.region) == ["HK"])
    #expect(LocaleTags.find(locale: "zh_MO", languages: [], inputSources: "").map(\.region) == ["MO"])
    #expect(LocaleTags.find(locale: "zh_CN", languages: [], inputSources: "").map(\.region) == ["CN"])
    #expect(LocaleTags.find(locale: "en_US@rg=hkzzzz", languages: [], inputSources: "").map(\.region) == ["HK"])
    #expect(LocaleTags.find(locale: "", languages: [], inputSources: "com.apple.inputmethod.SCIM").map(\.region) == ["CN"])
    #expect(LocaleTags.find(locale: "", languages: [], inputSources: "com.apple.inputmethod.TCIM").map(\.region) == ["HK"])
    #expect(LocaleTags.find(locale: "en_US", languages: ["en-US"], inputSources: "documentation").isEmpty)
    let tags = LocaleTags.find(locale: "en_HK", languages: ["zh-Hans-CN"], inputSources: "")
    #expect(LocaleTags.regionsThatDiffer(tags, from: ["JP"]) == ["HK", "CN"])
    #expect(LocaleTags.regionsThatDiffer(tags, from: ["HK"]) == ["CN"])
    #expect(LocaleTags.regionsThatDiffer(
        LocaleTags.find(locale: "en_HK", languages: [], inputSources: ""),
        from: ["HK"]
    ).isEmpty)
    #expect(LocaleTags.regionsThatDiffer(tags, from: []).isEmpty)

    let dns = """
    resolver #1
      nameserver[0] : 162.252.172.57
      if_index : 12 (utun4)
    resolver #2
      nameserver[0] : 192.168.1.1
      if_index : 14 (en0)
    DNS configuration (for scoped queries)
      if_index : 1 (en1)
    """
    #expect(DNSParse.interfaces(in: dns) == ["utun4", "en0"])
    #expect(RouteParse.isPhysical("en0", hardware: ["en0"]))
    #expect(!RouteParse.isPhysical("utun4", hardware: ["en0"]))
}
