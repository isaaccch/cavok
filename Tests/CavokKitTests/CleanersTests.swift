import Foundation
import Testing
@testable import CavokKit

@Test func shellCommentLeavesUnrelatedLines() {
    let text = """
    export PATH="$PATH:/usr/local/bin"
    export HTTPS_PROXY=http://127.0.0.1:7890
    # export HTTP_PROXY=http://old
    launchctl setenv ANTHROPIC_BASE_URL https://relay.example
    echo HTTPS_PROXY is not an assignment
    """
    let edit = ShellCleaner.commenting(text, date: "2026-11-12")
    #expect(edit.removed == ["HTTPS_PROXY", "ANTHROPIC_BASE_URL"])
    #expect(edit.text.contains("export PATH=\"$PATH:/usr/local/bin\""))
    #expect(edit.text.contains("# export HTTP_PROXY=http://old"))
    #expect(edit.text.contains("# cavok 2026-11-12: commented out HTTPS_PROXY"))
    #expect(edit.text.contains("echo HTTPS_PROXY is not an assignment"))
    #expect(ShellCleaner.hits(in: edit.text, file: ".zshrc").isEmpty)
}

@Test func settingsKeepOfficialTokenAndDropRelay() throws {
    let relay = Data(#"""
    {"env":{"ANTHROPIC_BASE_URL":"https://relay.example","ANTHROPIC_AUTH_TOKEN":"sk-relay","HTTPS_PROXY":"http://127.0.0.1:1"},"theme":"dark"}
    """#.utf8)
    let relayEdit = try SettingsCleaner.cleaning(relay)
    #expect(relayEdit.removed == ["ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL", "HTTPS_PROXY"])
    let relayObject = try JSONSerialization.jsonObject(with: #require(relayEdit.data)) as? [String: Any]
    #expect(relayObject?["theme"] as? String == "dark")
    #expect(relayObject?["env"] == nil)

    let official = Data(#"""
    {"env":{"ANTHROPIC_BASE_URL":"https://api.anthropic.com","ANTHROPIC_AUTH_TOKEN":"sk-live"}}
    """#.utf8)
    let officialEdit = try SettingsCleaner.cleaning(official)
    #expect(officialEdit.removed.isEmpty)
    #expect(officialEdit.data == nil)
}

@Test func settingsDropProxyAndKeepOtherEnv() throws {
    let raw = Data(#"""
    {"env":{"HTTP_PROXY":"http://127.0.0.1:9","CLAUDE_CODE_EFFORT":"high"}}
    """#.utf8)
    let edit = try SettingsCleaner.cleaning(raw)
    #expect(edit.removed == ["HTTP_PROXY"])
    let object = try JSONSerialization.jsonObject(with: #require(edit.data)) as? [String: Any]
    let env = object?["env"] as? [String: String]
    #expect(env?["CLAUDE_CODE_EFFORT"] == "high")
    #expect(env?["HTTP_PROXY"] == nil)
}

@Test func traceAndServicesAndDNS() {
    let trace = "fl=1\nip=93.118.41.99\nts=1\nloc=JP\n"
    #expect(TraceParse.field("ip", in: trace) == "93.118.41.99")
    #expect(TraceParse.field("loc", in: trace) == "JP")
    #expect(TraceParse.field("missing", in: trace) == nil)

    let services = """
    An asterisk (*) denotes that a network service is disabled.
    *Bluetooth PAN
    Wi-Fi
    Surfshark. WireGuard®
    USB 10/100 LAN

    """
    #expect(ServiceList.changeable(from: services) == ["Wi-Fi", "USB 10/100 LAN"])

    let dns = """
    nameserver[0] : 162.252.172.57
    nameserver[1] : 162.252.172.57
    DNS configuration (for scoped queries)
    nameserver[0] : 192.168.124.1
    """
    #expect(DNSParse.nameservers(in: dns) == ["162.252.172.57"])
    #expect(RegionGate.allowsClaude("JP"))
    #expect(!RegionGate.allowsClaude("HK"))
    #expect(!RegionGate.allowsClaude(nil))
}
