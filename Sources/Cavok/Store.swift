import AppKit
import CavokKit
import Foundation

enum Tone: Equatable {
    case ok, warn, idle
}

enum FixAction: Equatable {
    case pin
    case cleanShell
    case cleanLaunchctl
    case cleanSettings
    case cleanCodex
    case cleanAll
    case disableProxy
    case quitApps
    case ipv6LinkLocal
    case ipv6Automatic
    case flushDNS
    case setTokyo
    case restoreZone
    case openClaude
    case openChatGPT
}

enum Confirm: Equatable {
    case ipv6, zone, proxy
}

struct FixRow: Identifiable, Equatable {
    enum ID: String, CaseIterable {
        case route, exit, chatgpt, reach, shell, launchctl, settings, codex, proxy, sockets, ipv6, dns, zone
    }

    var id: ID
    var title: String
    var detail: String
    var tone: Tone
    var button: String?
    var action: FixAction?
}

struct FixSection: Identifiable {
    var title: String
    var ids: [FixRow.ID]
    var id: String { title }
}

@MainActor
@Observable
final class FixStore {
    static let sections = [
        FixSection(title: "Exit", ids: [.route, .exit, .chatgpt, .reach]),
        FixSection(title: "Files and environment", ids: [.shell, .launchctl, .settings, .codex]),
        FixSection(title: "Network", ids: [.proxy, .sockets, .ipv6, .dns]),
        FixSection(title: "Time zone and locale", ids: [.zone]),
    ]

    private static let pinIPKey = "cavok.pinnedIP"
    private static let pinLocKey = "cavok.pinnedLoc"
    private static let zoneKey = "cavok.previousTimeZone"
    private static let ipv6Key = "cavok.ipv6Changed"
    nonisolated static let guardKey = "cavok.guardEnabled"
    nonisolated static let rootsKey = "cavok.workspaceRoots"

    var rows: [FixRow.ID: FixRow]
    var note = ""
    var busy = false
    var guardOn: Bool
    var packetDropState: PacketDropState = .off
    var workspacePaths: [String]
    let preview: Bool
    private var didStart = false
    private var report = MachineReport()
    private var watchdog: Watchdog?
    private var dropControl: PacketDropControl?
    private var socketLeakReinspected = false
    @ObservationIgnored private var inspectGeneration = 0

    var blockingReason: String? {
        SessionGate.blockingReason(facts())
    }

    var routeIsTunnel: Bool {
        report.routeIsTunnel
    }

    var claudeRemoteIP: String? {
        report.claudeRemoteIP
    }

    var chatgptRemoteIP: String? {
        report.chatgptRemoteIP
    }

    func exitDrifted(_ seen: ExitReading) -> Bool {
        ExitDrift.changed(from: lastExit, to: seen)
    }

    func exitWentQuiet(_ seen: ExitReading) -> Bool {
        ExitDrift.wentQuiet(from: lastExit, to: seen)
    }

    private var lastExit: ExitReading {
        ExitReading(
            claudeIP: report.ip,
            claudeLoc: report.loc,
            chatgptIP: report.chatgptIP,
            chatgptLoc: report.chatgptLoc
        )
    }

    var menuSymbol: String {
        if busy { return "arrow.clockwise" }
        if rows.values.contains(where: { $0.tone == .warn }) { return "exclamationmark.triangle" }
        if rows[.exit]?.tone == .ok { return "checkmark.circle" }
        return "network"
    }

    var menuTitle: String {
        if busy { return "…" }
        if report.routeIsPhysical { return "LAN" }
        if let loc = report.loc, !loc.isEmpty { return loc }
        return "Cavok"
    }

    var canClean: Bool {
        rows[.shell]?.action != nil || rows[.launchctl]?.action != nil || rows[.settings]?.action != nil || rows[.codex]?.action != nil
    }

    var canOpen: Bool {
        if preview { return true }
        if guardOn && !packetDropArmed { return false }
        return SessionGate.canOpen(facts())
    }

    var packetDropArmed: Bool {
        packetDropState == .armed
    }

    var packetDropNeedsApproval: Bool {
        packetDropState == .needsApproval
    }

    var packetDropLine: String {
        switch packetDropState {
        case .armed:
            "Packet drop is on. Wi-Fi and Ethernet stay closed for Claude and ChatGPT."
        case .notBundled:
            "Packet drop is not armed. This build does not include the filter extension. Open stays off."
        case .needsApproval:
            "Packet drop needs your approval in System Settings. Open stays off."
        case .failed(let reason):
            "Packet drop is not armed. \(reason.hasSuffix(".") ? reason : reason + ".") Open stays off."
        case .off:
            "Packet drop is not armed. Open stays off."
        }
    }

    var openHelp: String {
        if !preview && guardOn && !packetDropArmed {
            return packetDropLine
        }
        if canOpen {
            return "Open while Claude and ChatGPT share this exit."
        }
        var check = facts()
        if check.pinnedIP == nil, let ip = check.claudeIP {
            check.pinnedIP = ip
            if SessionGate.canOpen(check) {
                return "Pin the shared exit first. Open turns on after that."
            }
        }
        return "Stays off until both exits match an allowed country on the tunnel, with no leak, leftover, or socket on Wi-Fi or Ethernet."
    }

    init(preview: Bool = ProcessInfo.processInfo.environment["APP_SNAPSHOT"] != nil) {
        self.preview = preview
        rows = preview ? Self.sample : Self.waiting
        if UserDefaults.standard.object(forKey: Self.guardKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.guardKey)
        }
        guardOn = UserDefaults.standard.bool(forKey: Self.guardKey)
        workspacePaths = Self.workspaceRoots().map(\.path)
    }

    func setGuard(_ on: Bool) {
        guardOn = on
        UserDefaults.standard.set(on, forKey: Self.guardKey)
        watchdog?.refresh()
        dropControl?.setEnabled(on)
    }

    func openExtensionSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    func pickRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.prompt = "Add Folder"
        panel.message = "Cavok looks in this folder for .claude/settings.json and settings.local.json."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var paths = UserDefaults.standard.stringArray(forKey: Self.rootsKey) ?? []
        if !paths.contains(url.path) { paths.append(url.path) }
        UserDefaults.standard.set(paths, forKey: Self.rootsKey)
        workspacePaths = paths
        inspect()
    }

    func removeRoot(_ path: String) {
        var paths = UserDefaults.standard.stringArray(forKey: Self.rootsKey) ?? []
        paths.removeAll { $0 == path }
        UserDefaults.standard.set(paths, forKey: Self.rootsKey)
        workspacePaths = paths
        inspect()
    }

    func inspectIfNeeded() {
        guard !preview, !didStart else { return }
        didStart = true
        if watchdog == nil {
            let dog = Watchdog(store: self)
            watchdog = dog
            dog.start()
        }
        if dropControl == nil {
            let control = PacketDropControl()
            control.onChange = { [weak self] state in
                self?.packetDropState = state
            }
            dropControl = control
            CavokActions.disablePacketDrop = { [weak control] in
                control?.setEnabled(false)
            }
            if guardOn { control.setEnabled(true) }
        }
        inspect()
    }

    func inspect(keepNote: Bool = false) {
        guard !preview else { return }
        busy = true
        if !keepNote { note = "Checking…" }
        inspectGeneration += 1
        let generation = inspectGeneration
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = Self.workspaceRoots()
        Task {
            let report = await Machine.inspect(home: home, workspaceRoots: roots)
            guard generation == self.inspectGeneration else { return }
            self.report = report
            self.rows = Self.makeRows(
                report,
                pinned: UserDefaults.standard.string(forKey: Self.pinIPKey),
                pinnedLoc: UserDefaults.standard.string(forKey: Self.pinLocKey),
                ipv6Changed: UserDefaults.standard.bool(forKey: Self.ipv6Key),
                previousZone: UserDefaults.standard.string(forKey: Self.zoneKey)
            )
            self.busy = false
            if !keepNote { self.note = "" }
            self.watchdog?.refresh()
            self.enforceGuard()
        }
    }

    func ask(_ row: FixRow, present: (Confirm) -> Void) {
        switch row.action {
        case .ipv6LinkLocal: present(.ipv6)
        case .setTokyo: present(.zone)
        case .disableProxy: present(.proxy)
        case .some(let action): perform(action)
        case nil: break
        }
    }

    func perform(_ action: FixAction) {
        guard !preview else { return }
        switch action {
        case .openClaude:
            openClaude()
        case .openChatGPT:
            openChatGPT()
        case .pin:
            pin()
        case .quitApps:
            quitApps()
        default:
            apply(action)
        }
    }

    private func facts() -> SessionFacts {
        var hosts: [SessionFacts.IPv6Sighting] = []
        if report.ipv6Claude.ip != nil {
            hosts.append(SessionFacts.IPv6Sighting(host: report.ipv6Claude.host, loc: report.ipv6Claude.loc, ipv4Loc: report.loc))
        }
        if report.ipv6ChatGPT.ip != nil {
            hosts.append(SessionFacts.IPv6Sighting(host: report.ipv6ChatGPT.host, loc: report.ipv6ChatGPT.loc, ipv4Loc: report.chatgptLoc))
        }
        return SessionFacts(
            routeIsPhysical: report.routeIsPhysical,
            routeIsTunnel: report.routeIsTunnel,
            routeInterface: report.routeInterface,
            claudeRouteIsPhysical: report.claudeRouteIsPhysical,
            claudeRouteInterface: report.claudeRouteInterface,
            chatgptRouteIsPhysical: report.chatgptRouteIsPhysical,
            chatgptRouteInterface: report.chatgptRouteInterface,
            claudeIP: report.ip,
            claudeLoc: report.loc,
            chatgptIP: report.chatgptIP,
            chatgptLoc: report.chatgptLoc,
            pinnedIP: UserDefaults.standard.string(forKey: Self.pinIPKey),
            socketLeak: !report.socketLeaks.isEmpty,
            shellLeftover: !report.shell.isEmpty,
            launchctlLeftover: !report.launchctl.isEmpty,
            claudeConfigLeftover: report.configHits.contains { !$0.keys.isEmpty },
            codexLeftover: !report.codexKeys.isEmpty,
            proxyLeftover: !report.proxyEnabled.isEmpty,
            ipv6RouteIsPhysical: report.ipv6RouteIsPhysical,
            ipv6RouteInterface: report.ipv6RouteInterface,
            ipv6Hosts: hosts
        )
    }

    private func enforceGuard() {
        guard guardOn, let reason = blockingReason else {
            socketLeakReinspected = false
            return
        }
        let labels = System.terminateProtected(force: true)
        if !labels.isEmpty, note.isEmpty {
            note = "Guard quit \(labels.sorted().joined(separator: ", ")). \(reason)"
        }
        guard reason == SessionGate.socketLeakReason else {
            socketLeakReinspected = false
            return
        }
        guard !socketLeakReinspected else { return }
        socketLeakReinspected = true
        inspect(keepNote: true)
    }

    private func pin() {
        guard let ip = report.ip, let other = report.chatgptIP, ip == other,
              let loc = report.loc, let otherLoc = report.chatgptLoc else {
            note = "Pin needs the same address from Claude and ChatGPT."
            return
        }
        guard loc.uppercased() == otherLoc.uppercased(), RegionGate.allows(loc), RegionGate.allows(otherLoc) else {
            let blocked = !RegionGate.allows(loc) || !RegionGate.allows(otherLoc)
            note = blocked
                ? "That exit is HK, CN, or MO. Cavok will not pin it."
                : "Pin needs the same country from Claude and ChatGPT."
            return
        }
        UserDefaults.standard.set(ip, forKey: Self.pinIPKey)
        UserDefaults.standard.set(loc, forKey: Self.pinLocKey)
        note = "Pinned \(ip)."
        inspect(keepNote: true)
    }

    private func openClaude() {
        guard canOpen else { return }
        let app = URL(fileURLWithPath: "/Applications/Claude.app")
        if FileManager.default.fileExists(atPath: app.path) {
            NSWorkspace.shared.open(app)
            note = "Opened Claude."
        } else {
            note = "Claude.app is not installed."
        }
    }

    private func openChatGPT() {
        guard canOpen else { return }
        let app = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        if FileManager.default.fileExists(atPath: app.path) {
            NSWorkspace.shared.open(app)
            note = "Opened ChatGPT."
        } else {
            note = "ChatGPT.app is not installed."
        }
    }

    private func quitApps() {
        let labels = System.terminateProtected(force: true)
        note = labels.isEmpty ? "Claude, ChatGPT, claude, and codex were not running." : "Quit \(labels.sorted().joined(separator: ", "))."
        inspect(keepNote: true)
    }

    private func apply(_ action: FixAction) {
        busy = true
        note = "Working…"
        let home = FileManager.default.homeDirectoryForCurrentUser
        let previous = TimeZone.current.identifier
        let savedZone = UserDefaults.standard.string(forKey: Self.zoneKey)
        let roots = Self.workspaceRoots()
        Task {
            let result = await Task.detached { () -> Exec in
                switch action {
                case .cleanShell:
                    return Self.edit { try HomeFiles.comment(home, date: Self.today()) }
                case .cleanLaunchctl:
                    let keys = System.launchctlSet()
                    System.unsetLaunchctl(keys)
                    return Exec(stdout: keys.joined(separator: ", "), code: 0)
                case .cleanSettings:
                    return Self.edit { try ConfigFiles.clean(home: home, roots: roots) }
                case .cleanCodex:
                    return Self.edit { try ConfigFiles.cleanCodex(home: home, date: Self.today()) }
                case .cleanAll:
                    return Self.cleanAll(home: home, roots: roots)
                case .disableProxy:
                    return System.disableProxies()
                case .ipv6LinkLocal:
                    return System.ipv6(linkLocal: true)
                case .ipv6Automatic:
                    return System.ipv6(linkLocal: false)
                case .flushDNS:
                    return System.flushDNS()
                case .setTokyo:
                    return System.setTimeZone("Asia/Tokyo", automatic: false)
                case .restoreZone:
                    guard let savedZone else { return Exec(stderr: "No saved time zone.", code: 1) }
                    return System.setTimeZone(savedZone, automatic: true)
                case .pin, .openClaude, .openChatGPT, .quitApps:
                    return Exec(code: 0)
                }
            }.value
            self.finish(action, result: result, previousZone: previous)
        }
    }

    private func finish(_ action: FixAction, result: Exec, previousZone: String) {
        if result.code == 0 {
            switch action {
            case .setTokyo:
                UserDefaults.standard.set(previousZone, forKey: Self.zoneKey)
            case .restoreZone:
                UserDefaults.standard.removeObject(forKey: Self.zoneKey)
            case .ipv6LinkLocal:
                UserDefaults.standard.set(true, forKey: Self.ipv6Key)
            case .ipv6Automatic:
                UserDefaults.standard.set(false, forKey: Self.ipv6Key)
            default:
                break
            }
            note = Self.success(action, result.stdout)
        } else if result.stderr.localizedCaseInsensitiveContains("cancel") {
            note = "Canceled."
        } else {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            note = detail.isEmpty ? "That did not finish." : detail
        }
        inspect(keepNote: true)
    }

    nonisolated private static func cleanAll(home: URL, roots: [URL]) -> Exec {
        var parts: [String] = []
        do {
            let shell = try HomeFiles.comment(home, date: today())
            if !shell.isEmpty { parts.append(shell) }
        } catch {
            return Exec(stderr: error.localizedDescription, code: 1)
        }
        let keys = System.launchctlSet()
        if !keys.isEmpty {
            System.unsetLaunchctl(keys)
            parts.append(keys.joined(separator: ", "))
        }
        do {
            let settings = try ConfigFiles.clean(home: home, roots: roots)
            if !settings.isEmpty { parts.append(settings) }
            let codex = try ConfigFiles.cleanCodex(home: home, date: today())
            if !codex.isEmpty { parts.append(codex) }
        } catch {
            return Exec(stderr: error.localizedDescription, code: 1)
        }
        return Exec(stdout: parts.joined(separator: "; "), code: 0)
    }

    nonisolated private static func edit(_ work: () throws -> String) -> Exec {
        do {
            return Exec(stdout: try work(), code: 0)
        } catch {
            return Exec(stderr: error.localizedDescription, code: 1)
        }
    }

    nonisolated private static func today() -> String {
        String(ISO8601DateFormatter().string(from: Date()).prefix(10))
    }

    nonisolated static func workspaceRoots() -> [URL] {
        let defaults = UserDefaults.standard
        let home = FileManager.default.homeDirectoryForCurrentUser
        if defaults.object(forKey: rootsKey) == nil {
            let seeds = ["Projects", "Developer"].map { home.appendingPathComponent($0).path }
                .filter { FileManager.default.fileExists(atPath: $0) }
            defaults.set(seeds, forKey: rootsKey)
        }
        return (defaults.stringArray(forKey: rootsKey) ?? []).map { URL(fileURLWithPath: $0) }
    }

    nonisolated private static func success(_ action: FixAction, _ stdout: String) -> String {
        let detail = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        switch action {
        case .cleanShell, .cleanSettings, .cleanCodex, .cleanAll, .cleanLaunchctl:
            let body = detail.isEmpty ? "Nothing needed a change." : "Cleaned \(detail)."
            return body + " The first copy is kept as .cavok-bak. Open a new terminal before using claude or ChatGPT."
        case .disableProxy:
            return "System proxies are off on Wi-Fi and Ethernet. Surfshark was left alone."
        case .quitApps:
            return detail
        case .ipv6LinkLocal:
            return "IPv6 on Wi-Fi and Ethernet is link-local. Surfshark was left alone."
        case .ipv6Automatic:
            return "IPv6 is back to automatic."
        case .flushDNS:
            return "DNS cache flushed."
        case .setTokyo:
            return "Time zone is Asia/Tokyo. Automatic time zone is off."
        case .restoreZone:
            return "The previous time zone is restored. Automatic time zone is on again."
        case .pin, .openClaude, .openChatGPT:
            return ""
        }
    }

    private static func makeRows(
        _ report: MachineReport,
        pinned: String?,
        pinnedLoc: String?,
        ipv6Changed: Bool,
        previousZone: String?
    ) -> [FixRow.ID: FixRow] {
        Dictionary(uniqueKeysWithValues: [
            route(report),
            exit(report, pinned: pinned, pinnedLoc: pinnedLoc),
            chatgpt(report, pinned: pinned, pinnedLoc: pinnedLoc),
            reach(report),
            shell(report),
            launchctl(report),
            settings(report),
            codex(report),
            proxy(report),
            sockets(report),
            ipv6(report, changed: ipv6Changed),
            dns(report),
            zone(report, previous: previousZone),
        ].map { ($0.id, $0) })
    }

    private static func route(_ report: MachineReport) -> FixRow {
        if let interface = report.routeInterface, report.routeIsTunnel {
            let v6 = report.ipv6RouteIsPhysical ? " IPv6 route is \(report.ipv6RouteInterface ?? "Wi-Fi")." : ""
            return FixRow(id: .route, title: "Tunnel route", detail: "IPv4 route is \(interface).\(v6)", tone: report.ipv6RouteIsPhysical ? .warn : .ok, button: nil, action: nil)
        }
        if report.routeIsPhysical {
            let name = report.routeInterface ?? "Wi-Fi"
            return FixRow(id: .route, title: "Tunnel route", detail: "IPv4 route is \(name). Cavok did not contact claude.ai or chatgpt.com.", tone: .warn, button: nil, action: nil)
        }
        return FixRow(id: .route, title: "Tunnel route", detail: report.routeError ?? "Could not read the IPv4 route.", tone: .idle, button: nil, action: nil)
    }

    private static func exit(_ report: MachineReport, pinned: String?, pinnedLoc: String?) -> FixRow {
        if report.traceSkipped {
            return FixRow(id: .exit, title: "Exit IP", detail: "No probe. The route is not on a tunnel.", tone: .warn, button: nil, action: nil)
        }
        guard let ip = report.ip, let loc = report.loc else {
            return FixRow(id: .exit, title: "Exit IP", detail: report.traceError ?? "Could not read the exit IP.", tone: .idle, button: nil, action: nil)
        }
        var parts = ["\(ip) · \(loc)."]
        if !RegionGate.allows(loc) { parts.append("This exit is HK, CN, or MO.") }
        if let other = report.chatgptIP, other != ip { parts.append("ChatGPT's address is \(other).") }
        if let otherLoc = report.chatgptLoc, report.chatgptIP != nil, otherLoc.uppercased() != loc.uppercased() {
            parts.append("ChatGPT's country is \(otherLoc).")
        }
        if let pinned, pinned != ip {
            parts.append("The pinned IP is \(pinned). Cavok cannot switch Surfshark.")
        } else if pinned == ip {
            parts.append("This is the IP you pinned.")
        } else if canOfferPin(report) {
            parts.append("Not pinned yet. Pin it while the Japan static server is connected.")
        }
        if let changed = countryChanged(loc, pinnedLoc: pinnedLoc) { parts.append(changed) }
        let offer = canOfferPin(report) && pinned != ip
        return FixRow(
            id: .exit,
            title: "Exit IP",
            detail: parts.joined(separator: " "),
            tone: exitTone(ip: ip, loc: loc, otherIP: report.chatgptIP, otherLoc: report.chatgptLoc, pinned: pinned),
            button: offer ? "Pin this IP" : nil,
            action: offer ? .pin : nil
        )
    }

    private static func chatgpt(_ report: MachineReport, pinned: String?, pinnedLoc: String?) -> FixRow {
        if report.traceSkipped {
            return FixRow(id: .chatgpt, title: "ChatGPT exit", detail: "No probe. The route is not on a tunnel.", tone: .warn, button: nil, action: nil)
        }
        guard let ip = report.chatgptIP, let loc = report.chatgptLoc else {
            return FixRow(id: .chatgpt, title: "ChatGPT exit", detail: report.chatgptError ?? "Could not read the ChatGPT exit.", tone: .idle, button: nil, action: nil)
        }
        var parts = ["\(ip) · \(loc)."]
        if !RegionGate.allows(loc) { parts.append("This exit is HK, CN, or MO.") }
        if let claudeIP = report.ip, claudeIP != ip { parts.append("Claude's address is \(claudeIP).") }
        if let claudeLoc = report.loc, report.ip != nil, claudeLoc.uppercased() != loc.uppercased() {
            parts.append("Claude's country is \(claudeLoc).")
        }
        if let pinned, pinned != ip {
            parts.append("The pinned IP is \(pinned).")
        } else if pinned == ip {
            parts.append("This is the IP you pinned.")
        } else if canOfferPin(report) {
            parts.append("Not pinned yet.")
        }
        if let changed = countryChanged(loc, pinnedLoc: pinnedLoc) { parts.append(changed) }
        return FixRow(
            id: .chatgpt,
            title: "ChatGPT exit",
            detail: parts.joined(separator: " "),
            tone: exitTone(ip: ip, loc: loc, otherIP: report.ip, otherLoc: report.loc, pinned: pinned),
            button: nil,
            action: nil
        )
    }

    private static func reach(_ report: MachineReport) -> FixRow {
        let title = "Service reachability"
        if report.traceSkipped {
            return FixRow(id: .reach, title: title, detail: "No probe. The route is not on a tunnel.", tone: .warn, button: nil, action: nil)
        }
        let claudeChallenged = report.claudePage.challenged
        let gptChallenged = report.chatgptPage.challenged
        let claudeOK = Self.reached(report.claudePage)
        let gptOK = Self.reached(report.chatgptPage)
        let detail: String
        if claudeOK, gptOK {
            detail = "curl reached claude.ai and chatgpt.com. This is curl's result and does not mean either app or a browser is blocked."
        } else {
            detail = reachPiece("claude.ai", report.claudePage)
                + " " + reachPiece("chatgpt.com", report.chatgptPage)
                + " This is curl's result and does not mean either app or a browser is blocked."
        }
        let tone: Tone
        if claudeChallenged || gptChallenged {
            tone = .warn
        } else if claudeOK, gptOK {
            tone = .ok
        } else {
            tone = .idle
        }
        return FixRow(id: .reach, title: title, detail: detail, tone: tone, button: nil, action: nil)
    }

    private static func reached(_ page: PageHeaders) -> Bool {
        guard let status = page.status, (200..<300).contains(status), !page.challenged else { return false }
        return true
    }

    private static func reachPiece(_ host: String, _ page: PageHeaders) -> String {
        if page.challenged {
            var bits: [String] = []
            if let status = page.status, status == 403 || status == 421 { bits.append("returned \(status)") }
            if page.mitigated { bits.append("sent cf-mitigated") }
            if bits.isEmpty { bits.append("was challenged") }
            return "\(host) \(bits.joined(separator: " and "))."
        }
        if let status = page.status {
            return "\(host) returned \(status)."
        }
        return "\(host) did not answer."
    }

    private static func canOfferPin(_ report: MachineReport) -> Bool {
        guard let ip = report.ip, let loc = report.loc else { return false }
        guard report.chatgptIP == ip, let other = report.chatgptLoc else { return false }
        guard loc.uppercased() == other.uppercased() else { return false }
        return RegionGate.allows(loc)
    }

    private static func exitTone(ip: String, loc: String, otherIP: String?, otherLoc: String?, pinned: String?) -> Tone {
        if !RegionGate.allows(loc) { return .warn }
        if let pinned, pinned != ip { return .warn }
        if let otherIP, otherIP != ip { return .warn }
        if let otherLoc, otherLoc.uppercased() != loc.uppercased() { return .warn }
        if pinned == ip { return .ok }
        if pinned == nil, otherIP == ip, otherLoc?.uppercased() == loc.uppercased() { return .warn }
        return .idle
    }

    private static func countryChanged(_ current: String, pinnedLoc: String?) -> String? {
        guard let pinnedLoc, !pinnedLoc.isEmpty, pinnedLoc.uppercased() != current.uppercased() else { return nil }
        return "Pinned country was \(pinnedLoc)."
    }

    private static func shell(_ report: MachineReport) -> FixRow {
        guard !report.shell.isEmpty else {
            return FixRow(id: .shell, title: "Shell startup files", detail: "No proxy or custom API address in zsh or bash startup files.", tone: .ok, button: nil, action: nil)
        }
        let names = Dictionary(grouping: report.shell, by: \.file)
        let parts = ShellCleaner.fileNames.compactMap { file -> String? in
            guard let hits = names[file], !hits.isEmpty else { return nil }
            let unique = Array(Set(hits.map(\.name))).sorted().joined(separator: ", ")
            return "\(file) sets \(unique)"
        }
        return FixRow(id: .shell, title: "Shell startup files", detail: parts.joined(separator: ". ") + ".", tone: .warn, button: "Comment out", action: .cleanShell)
    }

    private static func launchctl(_ report: MachineReport) -> FixRow {
        guard !report.launchctl.isEmpty else {
            return FixRow(id: .launchctl, title: "Login environment", detail: "No proxy or custom API address is set for apps launched from this login.", tone: .ok, button: nil, action: nil)
        }
        return FixRow(id: .launchctl, title: "Login environment", detail: "\(report.launchctl.joined(separator: ", ")) is set for apps launched from this login.", tone: .warn, button: "Remove", action: .cleanLaunchctl)
    }

    private static func settings(_ report: MachineReport) -> FixRow {
        let flagged = report.configHits.filter { !$0.keys.isEmpty }
        if flagged.isEmpty, let error = report.configHits.compactMap(\.error).first {
            return FixRow(id: .settings, title: "Claude configs", detail: error, tone: .warn, button: nil, action: nil)
        }
        if flagged.isEmpty {
            return FixRow(id: .settings, title: "Claude configs", detail: "No relay or proxy keys in Claude settings, ~/.claude.json, or the project folders.", tone: .ok, button: nil, action: nil)
        }
        let parts = flagged.map { "\($0.file) has \($0.keys.joined(separator: ", "))" }
        return FixRow(id: .settings, title: "Claude configs", detail: parts.joined(separator: ". ") + ".", tone: .warn, button: "Remove", action: .cleanSettings)
    }

    private static func codex(_ report: MachineReport) -> FixRow {
        if let error = report.codexError {
            return FixRow(id: .codex, title: "Codex config", detail: error, tone: .warn, button: nil, action: nil)
        }
        if report.codexMissing {
            return FixRow(id: .codex, title: "Codex config", detail: "No ~/.codex/config.toml. Nothing to clean.", tone: .ok, button: nil, action: nil)
        }
        if report.codexKeys.isEmpty {
            return FixRow(id: .codex, title: "Codex config", detail: "No custom base URL in ~/.codex/config.toml.", tone: .ok, button: nil, action: nil)
        }
        return FixRow(id: .codex, title: "Codex config", detail: "~/.codex/config.toml has \(report.codexKeys.joined(separator: ", ")).", tone: .warn, button: "Comment out", action: .cleanCodex)
    }

    private static func proxy(_ report: MachineReport) -> FixRow {
        if report.proxyEnabled.isEmpty {
            return FixRow(id: .proxy, title: "System proxy", detail: "HTTP, HTTPS, SOCKS, and automatic proxy are off.", tone: .ok, button: nil, action: nil)
        }
        return FixRow(id: .proxy, title: "System proxy", detail: "\(report.proxyEnabled.joined(separator: ", ")) is on. Claude and ChatGPT follow the macOS proxy.", tone: .warn, button: "Turn off", action: .disableProxy)
    }

    private static func sockets(_ report: MachineReport) -> FixRow {
        if report.socketLeaks.isEmpty {
            return FixRow(id: .sockets, title: "Open app sockets", detail: "No Claude, ChatGPT, Codex, or child-process connection is using a Wi-Fi or Ethernet address.", tone: .ok, button: nil, action: nil)
        }
        let parts = report.socketLeaks.map { "\($0.command) \($0.localAddress)" }
        return FixRow(id: .sockets, title: "Open app sockets", detail: parts.joined(separator: ", ") + ".", tone: .warn, button: "Quit apps", action: .quitApps)
    }

    private static func ipv6(_ report: MachineReport, changed: Bool) -> FixRow {
        let restore = changed ? "Restore automatic" : nil
        if report.ipv6Missing {
            return FixRow(id: .ipv6, title: "IPv6", detail: "IPv6 not present", tone: .idle, button: restore, action: changed ? .ipv6Automatic : nil)
        }
        if report.ipv6Skipped {
            return FixRow(
                id: .ipv6,
                title: "IPv6",
                detail: "IPv6 route is \(report.ipv6RouteInterface ?? "Wi-Fi"). Cavok did not send an IPv6 probe.",
                tone: .warn,
                button: "Set link-local",
                action: .ipv6LinkLocal
            )
        }
        let leaked = ipv6Leaked(report)
        let bothAnswered = report.ipv6Claude.ip != nil && report.ipv6ChatGPT.ip != nil
        let detail = report.ipv6Claude.ip == nil && report.ipv6ChatGPT.ip == nil
            ? "claude.ai and chatgpt.com did not answer on IPv6."
            : "\(ipv6Piece(report.ipv6Claude, fallback: "claude.ai")) \(ipv6Piece(report.ipv6ChatGPT, fallback: "chatgpt.com"))"
        let tone: Tone = leaked ? .warn : (bothAnswered ? .ok : .idle)
        return FixRow(
            id: .ipv6,
            title: "IPv6",
            detail: detail,
            tone: tone,
            button: leaked ? "Set link-local" : restore,
            action: leaked ? .ipv6LinkLocal : (changed ? .ipv6Automatic : nil)
        )
    }

    private static func ipv6Piece(_ result: IPv6HostResult, fallback: String) -> String {
        let host = result.host.isEmpty ? fallback : result.host
        guard let ip = result.ip else { return "\(host) did not answer on IPv6." }
        let loc = result.loc ?? "an unknown country"
        return "\(host) sees IPv6 \(ip) in \(loc)."
    }

    private static func ipv6Leaked(_ report: MachineReport) -> Bool {
        func bad(_ result: IPv6HostResult, v4: String?) -> Bool {
            guard result.ip != nil else { return false }
            if let loc = result.loc, RegionGate.blocked.contains(loc.uppercased()) { return true }
            if let v4, !v4.isEmpty, result.loc?.uppercased() != v4.uppercased() { return true }
            return false
        }
        if bad(report.ipv6Claude, v4: report.loc) || bad(report.ipv6ChatGPT, v4: report.chatgptLoc) { return true }
        if let left = report.ipv6Claude.loc, let right = report.ipv6ChatGPT.loc,
           report.ipv6Claude.ip != nil, report.ipv6ChatGPT.ip != nil,
           left.uppercased() != right.uppercased() {
            return true
        }
        return false
    }

    private static func dns(_ report: MachineReport) -> FixRow {
        let shown = report.nameservers.prefix(4).joined(separator: ", ")
        let listed = shown.isEmpty ? "No resolver addresses were read." : "Resolvers in use: \(shown)."
        if report.routeIsTunnel, !report.dnsPhysicalInterfaces.isEmpty {
            let names = report.dnsPhysicalInterfaces.joined(separator: ", ")
            return FixRow(
                id: .dns,
                title: "DNS",
                detail: "\(listed) A resolver is on \(names) while the IPv4 route is a tunnel. Flush only clears the cache.",
                tone: .warn,
                button: "Flush",
                action: .flushDNS
            )
        }
        return FixRow(id: .dns, title: "DNS", detail: "\(listed) Flush only clears the cache.", tone: .idle, button: "Flush", action: .flushDNS)
    }

    private static func zone(_ report: MachineReport, previous: String?) -> FixRow {
        let zone = report.timeZone
        let exits = [report.loc, report.chatgptLoc].compactMap { $0 }.filter { !$0.isEmpty }
        let japan = exits.contains { $0.uppercased() == "JP" }
        let tags = LocaleTags.find(locale: report.appleLocale, languages: report.appleLanguages, inputSources: report.inputSources)
        let mismatched = LocaleTags.regionsThatDiffer(tags, from: exits)
        var sentences = ["This Mac is on \(zone)."]
        if japan, zone != "Asia/Tokyo" { sentences.append("An exit is JP.") }
        if !mismatched.isEmpty {
            sentences.append("Locale or input source includes \(mismatched.joined(separator: ", ")) while an exit country is not that country.")
        }
        let warn = (japan && zone != "Asia/Tokyo") || !mismatched.isEmpty
        let tone: Tone = warn ? .warn : (zone == "Asia/Tokyo" ? .ok : .idle)
        if zone == "Asia/Tokyo" {
            let button = previous == nil ? nil : "Restore \(previous ?? "")"
            return FixRow(id: .zone, title: "Time zone and locale", detail: sentences.joined(separator: " "), tone: tone, button: button, action: previous == nil ? nil : .restoreZone)
        }
        return FixRow(id: .zone, title: "Time zone and locale", detail: sentences.joined(separator: " "), tone: tone, button: "Set to Tokyo", action: .setTokyo)
    }

    private static let waiting: [FixRow.ID: FixRow] = Dictionary(uniqueKeysWithValues: FixRow.ID.allCases.map { id in
        (id, FixRow(id: id, title: title(id), detail: "Checking…", tone: .idle, button: nil, action: nil))
    })

    private static func title(_ id: FixRow.ID) -> String {
        switch id {
        case .route: "Tunnel route"
        case .exit: "Exit IP"
        case .chatgpt: "ChatGPT exit"
        case .reach: "Service reachability"
        case .shell: "Shell startup files"
        case .launchctl: "Login environment"
        case .settings: "Claude configs"
        case .codex: "Codex config"
        case .proxy: "System proxy"
        case .sockets: "Open app sockets"
        case .ipv6: "IPv6"
        case .dns: "DNS"
        case .zone: "Time zone and locale"
        }
    }

    static let sample: [FixRow.ID: FixRow] = [
        .route: FixRow(id: .route, title: "Tunnel route", detail: "IPv4 route is utun4.", tone: .ok, button: nil, action: nil),
        .exit: FixRow(id: .exit, title: "Exit IP", detail: "93.118.41.99 · JP. This is the IP you pinned.", tone: .ok, button: nil, action: nil),
        .chatgpt: FixRow(id: .chatgpt, title: "ChatGPT exit", detail: "93.118.41.99 · JP. This is the IP you pinned.", tone: .ok, button: nil, action: nil),
        .reach: FixRow(id: .reach, title: "Service reachability", detail: "curl reached claude.ai and chatgpt.com. This is curl's result and does not mean either app or a browser is blocked.", tone: .ok, button: nil, action: nil),
        .shell: FixRow(id: .shell, title: "Shell startup files", detail: ".zshrc sets HTTPS_PROXY.", tone: .warn, button: "Comment out", action: .cleanShell),
        .launchctl: FixRow(id: .launchctl, title: "Login environment", detail: "No proxy or custom API address is set for apps launched from this login.", tone: .ok, button: nil, action: nil),
        .settings: FixRow(id: .settings, title: "Claude configs", detail: "~/.claude/settings.json has ANTHROPIC_BASE_URL.", tone: .warn, button: "Remove", action: .cleanSettings),
        .codex: FixRow(id: .codex, title: "Codex config", detail: "No custom base URL in ~/.codex/config.toml.", tone: .ok, button: nil, action: nil),
        .proxy: FixRow(id: .proxy, title: "System proxy", detail: "HTTPEnable is on. Claude and ChatGPT follow the macOS proxy.", tone: .warn, button: "Turn off", action: .disableProxy),
        .sockets: FixRow(id: .sockets, title: "Open app sockets", detail: "No Claude, ChatGPT, Codex, or child-process connection is using a Wi-Fi or Ethernet address.", tone: .ok, button: nil, action: nil),
        .ipv6: FixRow(id: .ipv6, title: "IPv6", detail: "claude.ai and chatgpt.com did not answer on IPv6.", tone: .idle, button: nil, action: nil),
        .dns: FixRow(id: .dns, title: "DNS", detail: "Resolvers in use: 162.252.172.57, 149.154.159.92. A resolver is on en0 while the IPv4 route is a tunnel. Flush only clears the cache.", tone: .warn, button: "Flush", action: .flushDNS),
        .zone: FixRow(id: .zone, title: "Time zone and locale", detail: "This Mac is on Asia/Hong_Kong. An exit is JP.", tone: .warn, button: "Set to Tokyo", action: .setTokyo),
    ]
}
