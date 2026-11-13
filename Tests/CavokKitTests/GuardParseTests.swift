import Foundation
import Testing
@testable import CavokKit

@Test func routeLookupUsesAPublicAddress() {
    #expect(RouteQuery.ipv4Destination == "1.1.1.1")
    let text = """
       route to: 1.1.1.1
    destination: 1.1.1.1
      interface: utun4
          flags: <UP,HOST,DONE>
    """
    #expect(RouteParse.interfaceName(in: text) == "utun4")
    #expect(RouteParse.interfaceName(in: "route: not in table\n") == nil)
    #expect(RouteParse.interfaceName(in: "   interface:   \n") == nil)
    #expect(RouteParse.isTunnel("utun4"))
    #expect(!RouteParse.isPhysical("utun4", hardware: ["en0"]))
    #expect(RouteParse.isPhysical("en0", hardware: ["en0"]))
    #expect(!RouteParse.isTunnel("en0"))
}

@Test func hardwarePortsAndProxyFlags() {
    let ports = """
    Hardware Port: Wi-Fi
    Device: en0

    Hardware Port: Thunderbolt Ethernet
    Device: en8
    """
    #expect(RouteParse.hardwareDevices(in: ports) == ["en0", "en8"])
    let proxy = """
    <dictionary> {
      HTTPEnable : 1
      HTTPSEnable : 0
      SOCKSEnable : 1
      ProxyAutoConfigEnable : 0
      ProxyAutoDiscoveryEnable : 1
    }
    """
    #expect(ProxyParse.enabled(in: proxy) == ["HTTPEnable", "SOCKSEnable", "ProxyAutoDiscoveryEnable"])
}

@Test func ifconfigAndSocketsIgnoreLoopback() {
    let ifconfig = """
    lo0: flags=8049<UP,LOOPBACK,RUNNING,MULTICAST> mtu 16384
    	inet 127.0.0.1 netmask 0xff000000
    en0: flags=8863<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST> mtu 1500
    	inet 192.168.1.20 netmask 0xffffff00 broadcast 192.168.1.255
    	inet6 fe80::abcd%en0 prefixlen 64
    utun4: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1424
    	inet 10.8.0.2 --> 10.8.0.1 netmask 0xffffffff
    """
    let ips = IfconfigParse.addresses(in: ifconfig, hardware: ["en0"])
    #expect(ips.contains("192.168.1.20"))
    #expect(ips.contains("fe80::abcd"))
    #expect(!ips.contains("127.0.0.1"))
    #expect(!ips.contains("10.8.0.2"))

    let lsof = """
    p10
    cnode
    n127.0.0.1:1111->127.0.0.1:2222
    n192.168.1.20:50000->104.18.0.1:443
    p11
    ccodex-aarch64-ap
    n10.8.0.2:40000->104.18.0.1:443
    """
    let leaks = SocketAudit.leaks(in: lsof, physicalIPs: ips)
    #expect(leaks.count == 1)
    #expect(leaks[0].pid == "10")
    #expect(leaks[0].localAddress == "192.168.1.20")
}

@Test func processMatchUsesTheCommandLine() {
    let ps = """
      10 node /opt/homebrew/bin/claude
      11 /Users/me/.npm/codex-aarch64-apple-darwin
      12 /Applications/Claude.app/Contents/MacOS/Claude
      13 /Applications/ChatGPT.app/Contents/MacOS/ChatGPT
      14 vim /Users/me/notes.txt
      15 node /usr/local/bin/unrelated
      16 vim claude
      17 grep claude
      18 man claude
      19 git commit -m "fix claude bug"
      20 node /Users/me/.npm/_npx/x/node_modules/@anthropic-ai/claude-code/cli.js
      21 node /Users/me/.local/share/claude/cli.js
      22 node /opt/homebrew/bin/codex
      23 grep codex
      24 node --experimental-strip-types /opt/homebrew/bin/claude-code
    """
    let found = ProcessMatch.protected(in: ps)
    #expect(found.map(\.pid) == [10, 11, 12, 13, 20, 21, 22, 24])
    #expect(found.map(\.label) == ["claude", "codex", "Claude", "ChatGPT", "claude", "claude", "codex", "claude"])
}

@Test func claudeJsonDropsRelayInsideMcpEnv() throws {
    let raw = Data(#"""
    {"userID":"abc","mcpServers":{"relay":{"command":"npx","env":{"HTTPS_PROXY":"http://127.0.0.1:9","ANTHROPIC_BASE_URL":"https://relay.example","ANTHROPIC_AUTH_TOKEN":"sk-relay"}}},"env":{"OPENAI_BASE_URL":"https://api.openai.com"}}
    """#.utf8)
    let edit = try ClaudeStateScanner.cleaning(raw)
    #expect(edit.removed == ["ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL", "HTTPS_PROXY"])
    let object = try JSONSerialization.jsonObject(with: #require(edit.data)) as? [String: Any]
    #expect(object?["userID"] as? String == "abc")
    let rootEnv = object?["env"] as? [String: String]
    #expect(rootEnv?["OPENAI_BASE_URL"] == "https://api.openai.com")
    let servers = object?["mcpServers"] as? [String: [String: Any]]
    #expect(servers?["relay"]?["env"] == nil)
}

@Test func projectScanFindsLocalSettingsAndSkipsNodeModules() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("cavok-scan-\(UUID().uuidString)")
    let kept = root.appendingPathComponent("app/.claude")
    let skipped = root.appendingPathComponent("app/node_modules/pkg/.claude")
    try FileManager.default.createDirectory(at: kept, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: skipped, withIntermediateDirectories: true)
    let relay = Data(#"""
    {"env":{"ANTHROPIC_BASE_URL":"https://relay.example"}}
    """#.utf8)
    try relay.write(to: kept.appendingPathComponent("settings.local.json"))
    try relay.write(to: skipped.appendingPathComponent("settings.json"))
    let hits = ProjectSettingsScanner.scan(roots: [root])
    #expect(hits.count == 1)
    #expect(hits[0].file.hasSuffix("app/.claude/settings.local.json"))
    #expect(hits[0].keys == ["ANTHROPIC_BASE_URL"])
    try FileManager.default.removeItem(at: root)
}

@Test func codexConfigFlagsCustomBaseURLOnly() {
    let text = """
    openai_base_url = "https://relay.example/v1"
    chatgpt_base_url = "https://chatgpt.com/backend-api"

    [model_providers.proxy]
    base_url = "http://127.0.0.1:9/v1"

    [model_providers.official]
    base_url = "https://us.api.openai.com/v1"

    [other]
    base_url = "https://relay.example/v1"
    """
    #expect(CodexConfig.hits(in: text) == ["openai_base_url", "model_providers.proxy.base_url"])
    let edit = CodexConfig.commenting(text, date: "2026-11-13")
    #expect(edit.removed == ["openai_base_url", "model_providers.proxy.base_url"])
    #expect(edit.text.contains("# cavok 2026-11-13: commented out openai_base_url"))
    #expect(edit.text.contains("chatgpt_base_url = \"https://chatgpt.com/backend-api\""))
    #expect(edit.text.contains("[other]"))
    #expect(CodexConfig.hits(in: edit.text).isEmpty)
}
