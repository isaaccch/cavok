import AppKit
import CavokKit
import Darwin
import Foundation

struct Exec: Sendable {
    var stdout = ""
    var stderr = ""
    var code: Int32 = 1
}

struct MachineReport: Sendable {
    var shell: [ShellHit] = []
    var launchctl: [String] = []
    var configHits: [ConfigHit] = []
    var codexKeys: [String] = []
    var codexMissing = false
    var codexError: String?
    var routeInterface: String?
    var routeIsTunnel = false
    var routeIsPhysical = false
    var routeError: String?
    var ipv6RouteInterface: String?
    var ipv6RouteIsPhysical = false
    var ip: String?
    var loc: String?
    var traceError: String?
    var traceSkipped = false
    var claudeRemoteIP: String?
    var claudeRouteInterface: String?
    var claudeRouteIsPhysical = false
    var chatgptIP: String?
    var chatgptLoc: String?
    var chatgptError: String?
    var chatgptRemoteIP: String?
    var chatgptRouteInterface: String?
    var chatgptRouteIsPhysical = false
    var ipv6Missing = false
    var ipv6Skipped = false
    var ipv6Claude = IPv6HostResult(host: "claude.ai")
    var ipv6ChatGPT = IPv6HostResult(host: "chatgpt.com")
    var claudePage = PageHeaders()
    var chatgptPage = PageHeaders()
    var claudePageError: String?
    var chatgptPageError: String?
    var proxyEnabled: [String] = []
    var socketLeaks: [SocketLeak] = []
    var nameservers: [String] = []
    var dnsInterfaces: [String] = []
    var dnsPhysicalInterfaces: [String] = []
    var timeZone = TimeZone.current.identifier
    var appleLocale = ""
    var appleLanguages: [String] = []
    var inputSources = ""
}

enum System {
    nonisolated static func run(_ path: String, _ args: [String]) -> Exec {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            return Exec(stderr: error.localizedDescription, code: 1)
        }
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        return Exec(stdout: stdout, stderr: stderr, code: process.terminationStatus)
    }

    nonisolated static func curlTrace(url: String, ipv6: Bool) -> Exec {
        var args = ["-sS", "--max-time", "5", "-w", "\nremote=%{remote_ip}", url]
        args.insert(ipv6 ? "-6" : "-4", at: 0)
        return run("/usr/bin/curl", args)
    }

    /// IPv4 response headers only. The body is discarded.
    nonisolated static func curlHeaders(url: String) -> Exec {
        run("/usr/bin/curl", ["-4", "-sS", "-D", "-", "-o", "/dev/null", "--max-time", "8", url])
    }

    nonisolated static func routeLookup(_ destination: String, inet6: Bool = false) -> Exec {
        var args = ["-n", "get"]
        if inet6 { args.append("-inet6") }
        args.append(destination)
        return run("/sbin/route", args)
    }

    /// Quits Claude, ChatGPT, claude, codex, and a child of those processes.
    /// The set is taken before the first signal. `force` is SIGKILL. Sleep uses a normal quit.
    @discardableResult
    nonisolated static func terminateProtected(force: Bool) -> [String] {
        let selfPid = ProcessInfo.processInfo.processIdentifier
        let snaps = ProcessTable.allSnaps()
        let protected = snaps.values.filter { $0.pid != selfPid && PacketDrop.isProtected(pid: $0.pid, snaps: snaps) }
        let apps = NSWorkspace.shared.runningApplications.filter { app in
            let path = app.bundleURL?.path ?? ""
            return path.contains("Claude.app") || path.contains("ChatGPT.app")
        }
        let signal: Int32 = force ? SIGKILL : SIGTERM
        for snap in protected {
            kill(snap.pid, signal)
        }
        for app in apps {
            if force { app.forceTerminate() } else { app.terminate() }
        }
        var labels = protected.map { ProcessMatch.quitName(for: $0.command) }
        if apps.contains(where: { $0.bundleURL?.path.contains("Claude.app") == true }), !labels.contains("Claude") {
            labels.append("Claude")
        }
        if apps.contains(where: { $0.bundleURL?.path.contains("ChatGPT.app") == true }), !labels.contains("ChatGPT") {
            labels.append("ChatGPT")
        }
        return Array(Set(labels)).sorted()
    }

    nonisolated static func socketLeaks() -> [SocketLeak] {
        let snaps = ProcessTable.allSnaps()
        let pids = snaps.keys.filter { PacketDrop.isProtected(pid: $0, snaps: snaps) }.sorted()
        guard !pids.isEmpty else { return [] }
        let ports = run("/usr/sbin/networksetup", ["-listallhardwareports"])
        let hardware = RouteParse.hardwareDevices(in: ports.stdout)
        let interfaces = run("/sbin/ifconfig", ["-a"])
        let physical = IfconfigParse.addresses(in: interfaces.stdout, hardware: hardware)
        let pidList = pids.map(String.init).joined(separator: ",")
        let listed = run("/usr/sbin/lsof", ["-a", "-p", pidList, "-i", "-n", "-P", "-F", "pcn"])
        return SocketAudit.leaks(in: listed.stdout, physicalIPs: physical)
    }

    nonisolated static func disableProxies() -> Exec {
        let lines = services().flatMap { service in
            [
                "-setwebproxystate",
                "-setsecurewebproxystate",
                "-setsocksfirewallproxystate",
                "-setautoproxystate",
                "-setproxyautodiscovery",
            ].map { flag in
                "/usr/sbin/networksetup \(flag) \(bashQuote(service)) off"
            }
        }
        guard !lines.isEmpty else { return Exec(stderr: "No Wi-Fi or Ethernet service to change.", code: 1) }
        return admin(lines.joined(separator: "\n"))
    }

    nonisolated static func launchctlSet() -> [String] {
        LeftoverName.launchctl.filter { key in
            let result = run("/bin/launchctl", ["getenv", key])
            return result.code == 0 && !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    nonisolated static func unsetLaunchctl(_ keys: [String]) {
        for key in keys {
            _ = run("/bin/launchctl", ["unsetenv", key])
        }
    }

    nonisolated static func services() -> [String] {
        let listed = run("/usr/sbin/networksetup", ["-listallnetworkservices"])
        return ServiceList.changeable(from: listed.stdout)
    }

    nonisolated static func ipv6(linkLocal: Bool) -> Exec {
        let flag = linkLocal ? "-setv6LinkLocal" : "-setv6automatic"
        let lines = services().map { "/usr/sbin/networksetup \(flag) \(bashQuote($0))" }
        guard !lines.isEmpty else { return Exec(stderr: "No Wi-Fi or Ethernet service to change.", code: 1) }
        return admin(lines.joined(separator: "\n"))
    }

    nonisolated static func flushDNS() -> Exec {
        admin("/usr/bin/dscacheutil -flushcache\n/usr/bin/killall -HUP mDNSResponder || true")
    }

    nonisolated static func setTimeZone(_ name: String, automatic: Bool) -> Exec {
        guard isSafeZone(name) else { return Exec(stderr: "The time zone name is not one Cavok will apply.", code: 1) }
        let auto = automatic ? "true" : "false"
        let quoted = bashQuote(name)
        return admin("""
        name=\(quoted)
        /usr/sbin/systemsetup -settimezone "$name"
        got=$(/usr/sbin/systemsetup -gettimezone)
        case "$got" in
          *"$name"*) ;;
          *) echo "Time zone did not stick: $got" >&2; exit 1 ;;
        esac
        /usr/bin/defaults write /Library/Preferences/com.apple.timezone.auto Active -bool \(auto)
        """)
    }

    nonisolated static func admin(_ body: String) -> Exec {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cavok-\(UUID().uuidString).sh")
        let script = "#!/bin/bash\nset -euo pipefail\n\(body)\n"
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        } catch {
            try? FileManager.default.removeItem(at: url)
            return Exec(stderr: error.localizedDescription, code: 1)
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let apple = "do shell script \"/bin/bash '\(url.path)'\" with administrator privileges"
        return run("/usr/bin/osascript", ["-e", apple])
    }

    nonisolated static func bashQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated static func isSafeZone(_ name: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_+/-")
        return !name.isEmpty && name.count < 80 && name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    nonisolated static func localePreferences() -> (locale: String, languages: [String], inputSources: String) {
        let domain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]
        let locale = domain["AppleLocale"] as? String ?? ""
        let languages = domain["AppleLanguages"] as? [String] ?? []
        let sources = domain["AppleEnabledInputSources"] as? [Any] ?? []
        let text = sources.flatMap { strings(in: $0) }.joined(separator: "\n")
        return (locale, languages, text)
    }

    nonisolated private static func strings(in value: Any) -> [String] {
        switch value {
        case let text as String:
            return [text]
        case let dict as [String: Any]:
            return dict.values.flatMap { strings(in: $0) }
        case let list as [Any]:
            return list.flatMap { strings(in: $0) }
        default:
            return []
        }
    }
}

enum FileBackup {
    nonisolated static func copyOnce(_ url: URL) throws {
        let backup = URL(fileURLWithPath: url.path + ".cavok-bak")
        guard BackupFile.shouldCreate(backupExists: FileManager.default.fileExists(atPath: backup.path)) else { return }
        try FileManager.default.copyItem(at: url, to: backup)
    }
}

enum FileReplace {
    /// Resolves a symlink, keeps the first backup beside that file, then writes it.
    nonisolated static func atomic(_ data: Data, to url: URL) throws {
        let target = url.resolvingSymlinksInPath()
        try FileBackup.copyOnce(target)
        try data.write(to: target, options: .atomic)
    }
}

enum HomeFiles {
    nonisolated static func scan(_ home: URL) -> [ShellHit] {
        ShellCleaner.fileNames.flatMap { name in
            let url = home.appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [ShellHit]() }
            return ShellCleaner.hits(in: text, file: name)
        }
    }

    nonisolated static func comment(_ home: URL, date: String) throws -> String {
        var notes: [String] = []
        for name in ShellCleaner.fileNames {
            let url = home.appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let edit = ShellCleaner.commenting(text, date: date)
            guard !edit.removed.isEmpty else { continue }
            try FileReplace.atomic(Data(edit.text.utf8), to: url)
            let unique = Array(Set(edit.removed)).sorted().joined(separator: ", ")
            notes.append("\(name) (\(unique))")
        }
        return notes.joined(separator: "; ")
    }

    nonisolated static func cleanSettings(_ home: URL) throws -> String {
        let url = home.appendingPathComponent(".claude/settings.json")
        let data = try Data(contentsOf: url)
        let edit = try SettingsCleaner.cleaning(data)
        guard let written = edit.data else { return "" }
        try FileReplace.atomic(written, to: url)
        return edit.removed.sorted().joined(separator: ", ")
    }
}

enum ConfigFiles {
    nonisolated static func hits(home: URL, roots: [URL]) -> [ConfigHit] {
        var hits: [ConfigHit] = []
        let global = home.appendingPathComponent(".claude/settings.json")
        if FileManager.default.fileExists(atPath: global.path) {
            hits.append(ProjectSettingsScanner.hit(at: global))
        }
        let state = home.appendingPathComponent(".claude.json")
        if FileManager.default.fileExists(atPath: state.path) {
            hits.append(claudeState(at: state))
        }
        hits.append(contentsOf: ProjectSettingsScanner.scan(roots: roots).filter { !$0.keys.isEmpty || $0.error != nil })
        return hits
    }

    nonisolated static func clean(home: URL, roots: [URL]) throws -> String {
        var notes: [String] = []
        let global = home.appendingPathComponent(".claude/settings.json")
        if FileManager.default.fileExists(atPath: global.path) {
            let cleaned = try HomeFiles.cleanSettings(home)
            if !cleaned.isEmpty { notes.append("~/.claude/settings.json (\(cleaned))") }
        }
        let state = home.appendingPathComponent(".claude.json")
        if FileManager.default.fileExists(atPath: state.path) {
            let cleaned = try writeJSON(state, edit: ClaudeStateScanner.cleaning)
            if !cleaned.isEmpty { notes.append("~/.claude.json (\(cleaned))") }
        }
        for hit in ProjectSettingsScanner.scan(roots: roots) where !hit.keys.isEmpty && hit.error == nil {
            let url = URL(fileURLWithPath: expand(hit.file, home: home))
            let cleaned = try writeJSON(url, edit: SettingsCleaner.cleaning)
            if !cleaned.isEmpty { notes.append("\(hit.file) (\(cleaned))") }
        }
        return notes.joined(separator: "; ")
    }

    nonisolated static func codexURL(home: URL) -> URL {
        if let env = ProcessInfo.processInfo.environment["CODEX_HOME"], !env.isEmpty {
            return URL(fileURLWithPath: env).appendingPathComponent("config.toml")
        }
        return home.appendingPathComponent(".codex/config.toml")
    }

    nonisolated static func codexKeys(home: URL) -> (missing: Bool, keys: [String], error: String?) {
        let url = codexURL(home: home)
        guard FileManager.default.fileExists(atPath: url.path) else { return (true, [], nil) }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return (false, [], "Could not read \(PathDisplay.abbreviate(url.path)).")
        }
        return (false, CodexConfig.hits(in: text), nil)
    }

    nonisolated static func cleanCodex(home: URL, date: String) throws -> String {
        let url = codexURL(home: home)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        let edit = CodexConfig.commenting(text, date: date)
        guard !edit.removed.isEmpty else { return "" }
        try FileReplace.atomic(Data(edit.text.utf8), to: url)
        return edit.removed.joined(separator: ", ")
    }

    nonisolated private static func claudeState(at url: URL) -> ConfigHit {
        let file = PathDisplay.abbreviate(url.path)
        do {
            let data = try Data(contentsOf: url)
            let keys = try ClaudeStateScanner.hits(in: data)
            return ConfigHit(file: file, keys: keys)
        } catch {
            return ConfigHit(file: file, keys: [], error: "Could not read \(file).")
        }
    }

    nonisolated private static func writeJSON(_ url: URL, edit: (Data) throws -> SettingsEdit) throws -> String {
        let data = try Data(contentsOf: url)
        let edit = try edit(data)
        guard let written = edit.data else { return "" }
        try FileReplace.atomic(written, to: url)
        return edit.removed.sorted().joined(separator: ", ")
    }

    nonisolated private static func expand(_ path: String, home: URL) -> String {
        if path == "~" { return home.path }
        if path.hasPrefix("~/") { return home.path + "/" + path.dropFirst(2) }
        return path
    }
}

enum Machine {
    /// The two IPv4 traces only. A failed request leaves that host empty.
    nonisolated static func traceExits() async -> ExitReading {
        async let claude = System.curlTrace(url: "https://claude.ai/cdn-cgi/trace", ipv6: false)
        async let chatgpt = System.curlTrace(url: "https://chatgpt.com/cdn-cgi/trace", ipv6: false)
        let claudeResult = await claude
        let chatgptResult = await chatgpt
        return ExitReading(
            claudeIP: traceField("ip", claudeResult),
            claudeLoc: traceField("loc", claudeResult),
            chatgptIP: traceField("ip", chatgptResult),
            chatgptLoc: traceField("loc", chatgptResult)
        )
    }

    nonisolated private static func traceField(_ name: String, _ result: Exec) -> String? {
        guard result.code == 0 else { return nil }
        return TraceParse.field(name, in: result.stdout)
    }

    nonisolated static func inspect(home: URL, workspaceRoots: [URL] = []) async -> MachineReport {
        let shell = HomeFiles.scan(home)
        let configs = ConfigFiles.hits(home: home, roots: workspaceRoots)
        let codex = ConfigFiles.codexKeys(home: home)
        async let route4 = System.routeLookup(RouteQuery.ipv4Destination)
        async let route6 = System.routeLookup(RouteQuery.ipv6Destination, inet6: true)
        async let ports = System.run("/usr/sbin/networksetup", ["-listallhardwareports"])
        async let proxy = System.run("/usr/sbin/scutil", ["--proxy"])
        async let dns = System.run("/usr/sbin/scutil", ["--dns"])
        async let vars = System.launchctlSet()
        let route4r = await route4
        let portsText = await ports
        let hardware = RouteParse.hardwareDevices(in: portsText.stdout)
        let iface = route4r.code == 0 ? RouteParse.interfaceName(in: route4r.stdout) : nil
        let tunnel = iface.map(RouteParse.isTunnel) ?? false
        let physical = iface.map { RouteParse.isPhysical($0, hardware: hardware) } ?? false
        let route6r = await route6
        let iface6 = route6r.code == 0 ? RouteParse.interfaceName(in: route6r.stdout) : nil

        var report = MachineReport()
        report.shell = shell
        report.launchctl = await vars
        report.configHits = configs
        report.codexMissing = codex.missing
        report.codexKeys = codex.keys
        report.codexError = codex.error
        report.routeInterface = iface
        report.routeIsTunnel = tunnel
        report.routeIsPhysical = physical
        if iface == nil {
            let reason = route4r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            report.routeError = reason.isEmpty ? "Could not read the IPv4 route." : reason
        }
        report.ipv6RouteInterface = iface6
        report.ipv6RouteIsPhysical = iface6.map { RouteParse.isPhysical($0, hardware: hardware) } ?? false
        report.ipv6Missing = iface6 == nil
        report.ipv6Skipped = report.ipv6RouteIsPhysical
        report.proxyEnabled = ProxyParse.enabled(in: (await proxy).stdout)
        report.socketLeaks = System.socketLeaks()
        let dnsText = (await dns).stdout
        report.nameservers = DNSParse.nameservers(in: dnsText)
        report.dnsInterfaces = DNSParse.interfaces(in: dnsText)
        report.dnsPhysicalInterfaces = report.dnsInterfaces.filter { RouteParse.isPhysical($0, hardware: hardware) }
        report.timeZone = TimeZone.current.identifier
        let locale = System.localePreferences()
        report.appleLocale = locale.locale
        report.appleLanguages = locale.languages
        report.inputSources = locale.inputSources

        guard tunnel else {
            report.traceSkipped = true
            return report
        }

        let probe6 = !report.ipv6Missing && !report.ipv6RouteIsPhysical
        async let v4 = System.curlTrace(url: "https://claude.ai/cdn-cgi/trace", ipv6: false)
        async let gpt = System.curlTrace(url: "https://chatgpt.com/cdn-cgi/trace", ipv6: false)
        async let headC = System.curlHeaders(url: "https://claude.ai/")
        async let headG = System.curlHeaders(url: "https://chatgpt.com/")
        async let v6c: Exec = probe6 ? System.curlTrace(url: "https://claude.ai/cdn-cgi/trace", ipv6: true) : Exec(code: 0)
        async let v6g: Exec = probe6 ? System.curlTrace(url: "https://chatgpt.com/cdn-cgi/trace", ipv6: true) : Exec(code: 0)
        let v4r = await v4
        let gptr = await gpt
        let headCr = await headC
        let headGr = await headG
        let c6 = await v6c
        let g6 = await v6g
        if v4r.code == 0 {
            report.ip = TraceParse.field("ip", in: v4r.stdout)
            report.loc = TraceParse.field("loc", in: v4r.stdout)
            report.claudeRemoteIP = TraceParse.remoteAddress(in: v4r.stdout)
            if report.ip == nil { report.traceError = "claude.ai answered without an IP." }
        } else {
            let reason = v4r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            report.traceError = reason.isEmpty ? "Could not reach claude.ai." : reason
        }
        if gptr.code == 0 {
            report.chatgptIP = TraceParse.field("ip", in: gptr.stdout)
            report.chatgptLoc = TraceParse.field("loc", in: gptr.stdout)
            report.chatgptRemoteIP = TraceParse.remoteAddress(in: gptr.stdout)
            if report.chatgptIP == nil { report.chatgptError = "chatgpt.com answered without an IP." }
        } else {
            let reason = gptr.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            report.chatgptError = reason.isEmpty ? "Could not reach chatgpt.com." : reason
        }
        if let remote = report.claudeRemoteIP {
            let name = RouteSocket.interface(for: remote)
            report.claudeRouteInterface = name
            report.claudeRouteIsPhysical = name.map { RouteParse.isPhysical($0, hardware: hardware) } ?? false
        }
        if let remote = report.chatgptRemoteIP {
            let name = RouteSocket.interface(for: remote)
            report.chatgptRouteInterface = name
            report.chatgptRouteIsPhysical = name.map { RouteParse.isPhysical($0, hardware: hardware) } ?? false
        }
        report.claudePage = ReachParse.parse(headCr.stdout)
        report.chatgptPage = ReachParse.parse(headGr.stdout)
        if headCr.code != 0, report.claudePage.status == nil, !report.claudePage.mitigated {
            let reason = headCr.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            report.claudePageError = reason.isEmpty ? "Could not read the headers." : reason
        }
        if headGr.code != 0, report.chatgptPage.status == nil, !report.chatgptPage.mitigated {
            let reason = headGr.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            report.chatgptPageError = reason.isEmpty ? "Could not read the headers." : reason
        }
        if probe6 {
            report.ipv6Claude = IPv6Trace.result(host: "claude.ai", trace: c6.code == 0 ? c6.stdout : "")
            report.ipv6ChatGPT = IPv6Trace.result(host: "chatgpt.com", trace: g6.code == 0 ? g6.stdout : "")
        }
        return report
    }
}
