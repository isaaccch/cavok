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
    case cleanAll
    case ipv6LinkLocal
    case ipv6Automatic
    case flushDNS
    case setTokyo
    case restoreZone
    case openClaude
}

enum Confirm: Equatable {
    case ipv6, zone
}

struct FixRow: Identifiable, Equatable {
    enum ID: String, CaseIterable {
        case exit, shell, launchctl, settings, ipv6, dns, zone
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
        FixSection(title: "Exit", ids: [.exit]),
        FixSection(title: "Files and environment", ids: [.shell, .launchctl, .settings]),
        FixSection(title: "Network", ids: [.ipv6, .dns]),
        FixSection(title: "Time zone", ids: [.zone]),
    ]

    private static let pinIPKey = "cavok.pinnedIP"
    private static let pinLocKey = "cavok.pinnedLoc"
    private static let zoneKey = "cavok.previousTimeZone"
    private static let ipv6Key = "cavok.ipv6Changed"

    var rows: [FixRow.ID: FixRow]
    var note = ""
    var busy = false
    let preview: Bool
    private var didStart = false
    private var report = MachineReport()

    var menuSymbol: String {
        if busy { return "arrow.clockwise" }
        if rows.values.contains(where: { $0.tone == .warn }) { return "exclamationmark.triangle" }
        if rows[.exit]?.tone == .ok { return "checkmark.circle" }
        return "network"
    }

    var menuTitle: String {
        if busy { return "…" }
        if let loc = report.loc, !loc.isEmpty { return loc }
        return "Cavok"
    }

    var canClean: Bool {
        rows[.shell]?.action != nil || rows[.launchctl]?.action != nil || rows[.settings]?.action != nil
    }

    var canOpenClaude: Bool {
        if preview { return true }
        return RegionGate.allowsClaude(report.loc) && report.ip != nil
    }

    init(preview: Bool = ProcessInfo.processInfo.environment["APP_SNAPSHOT"] != nil) {
        self.preview = preview
        rows = preview ? Self.sample : Self.waiting
    }

    func inspectIfNeeded() {
        guard !preview, !didStart else { return }
        didStart = true
        inspect()
    }

    func inspect(keepNote: Bool = false) {
        guard !preview else { return }
        busy = true
        if !keepNote { note = "Checking…" }
        let home = FileManager.default.homeDirectoryForCurrentUser
        Task {
            let report = await Machine.inspect(home: home)
            self.report = report
            self.rows = Self.makeRows(
                report,
                pinned: UserDefaults.standard.string(forKey: Self.pinIPKey),
                ipv6Changed: UserDefaults.standard.bool(forKey: Self.ipv6Key),
                previousZone: UserDefaults.standard.string(forKey: Self.zoneKey)
            )
            self.busy = false
            if !keepNote { self.note = "" }
        }
    }

    func ask(_ row: FixRow, present: (Confirm) -> Void) {
        switch row.action {
        case .ipv6LinkLocal: present(.ipv6)
        case .setTokyo: present(.zone)
        case .some(let action): perform(action)
        case nil: break
        }
    }

    func perform(_ action: FixAction) {
        guard !preview else { return }
        switch action {
        case .openClaude:
            openClaude()
        case .pin:
            pin()
        default:
            apply(action)
        }
    }

    private func pin() {
        guard let ip = report.ip else { return }
        UserDefaults.standard.set(ip, forKey: Self.pinIPKey)
        UserDefaults.standard.set(report.loc, forKey: Self.pinLocKey)
        note = "Pinned \(ip)."
        inspect(keepNote: true)
    }

    private func openClaude() {
        let app = URL(fileURLWithPath: "/Applications/Claude.app")
        if FileManager.default.fileExists(atPath: app.path) {
            NSWorkspace.shared.open(app)
            note = "Opened Claude."
        } else if let url = URL(string: "https://claude.ai") {
            NSWorkspace.shared.open(url)
            note = "Claude.app is not installed. Opened claude.ai."
        }
    }

    private func apply(_ action: FixAction) {
        busy = true
        note = "Working…"
        let home = FileManager.default.homeDirectoryForCurrentUser
        let previous = TimeZone.current.identifier
        let savedZone = UserDefaults.standard.string(forKey: Self.zoneKey)
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
                    return Self.edit { try HomeFiles.cleanSettings(home) }
                case .cleanAll:
                    return Self.cleanAll(home: home)
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
                case .pin, .openClaude:
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

    nonisolated private static func cleanAll(home: URL) -> Exec {
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
        let settingsURL = home.appendingPathComponent(".claude/settings.json")
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            do {
                let settings = try HomeFiles.cleanSettings(home)
                if !settings.isEmpty { parts.append(settings) }
            } catch {
                return Exec(stderr: error.localizedDescription, code: 1)
            }
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

    nonisolated private static func success(_ action: FixAction, _ stdout: String) -> String {
        let detail = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        switch action {
        case .cleanShell, .cleanSettings, .cleanAll, .cleanLaunchctl:
            let body = detail.isEmpty ? "Nothing needed a change." : "Cleaned \(detail)."
            return body + " A copy of any file that changed is saved next to it as .cavok-bak. Open a new terminal before using claude."
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
        case .pin, .openClaude:
            return ""
        }
    }

    private static func makeRows(
        _ report: MachineReport,
        pinned: String?,
        ipv6Changed: Bool,
        previousZone: String?
    ) -> [FixRow.ID: FixRow] {
        Dictionary(uniqueKeysWithValues: [
            exit(report, pinned: pinned),
            shell(report),
            launchctl(report),
            settings(report),
            ipv6(report, changed: ipv6Changed),
            dns(report),
            zone(report, previous: previousZone),
        ].map { ($0.id, $0) })
    }

    private static func exit(_ report: MachineReport, pinned: String?) -> FixRow {
        guard let ip = report.ip, let loc = report.loc else {
            return FixRow(id: .exit, title: "Exit IP", detail: report.traceError ?? "Could not read the exit IP.", tone: .idle, button: nil, action: nil)
        }
        let place = "\(ip) · \(loc)"
        if let pinned, pinned != ip {
            return FixRow(id: .exit, title: "Exit IP", detail: "\(place). The pinned IP is \(pinned). Cavok cannot switch Surfshark. Reconnect that server, or pin this one.", tone: .warn, button: "Pin this IP", action: .pin)
        }
        if pinned == ip {
            return FixRow(id: .exit, title: "Exit IP", detail: "\(place). This is the IP you pinned.", tone: RegionGate.allowsClaude(loc) ? .ok : .warn, button: nil, action: nil)
        }
        let tone: Tone = RegionGate.allowsClaude(loc) ? .idle : .warn
        let extra = RegionGate.allowsClaude(loc)
            ? "Not pinned yet. Pin it while the Japan static server is connected."
            : "This exit is HK, CN, or MO."
        return FixRow(id: .exit, title: "Exit IP", detail: "\(place). \(extra)", tone: tone, button: "Pin this IP", action: .pin)
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
        if let error = report.settingsError {
            return FixRow(id: .settings, title: "Claude Code settings", detail: error, tone: .idle, button: nil, action: nil)
        }
        if report.settingsMissing {
            return FixRow(id: .settings, title: "Claude Code settings", detail: "No ~/.claude/settings.json. Nothing to clean.", tone: .ok, button: nil, action: nil)
        }
        if report.settingsKeys.isEmpty {
            return FixRow(id: .settings, title: "Claude Code settings", detail: "No relay or proxy keys in ~/.claude/settings.json.", tone: .ok, button: nil, action: nil)
        }
        return FixRow(id: .settings, title: "Claude Code settings", detail: "~/.claude/settings.json has \(report.settingsKeys.joined(separator: ", ")).", tone: .warn, button: "Remove", action: .cleanSettings)
    }

    private static func ipv6(_ report: MachineReport, changed: Bool) -> FixRow {
        if report.ipv6Blocked {
            let restore = changed ? "Restore automatic" : nil
            return FixRow(
                id: .ipv6,
                title: "IPv6",
                detail: "claude.ai did not answer on IPv6.",
                tone: .ok,
                button: restore,
                action: changed ? .ipv6Automatic : nil
            )
        }
        let loc = report.ipv6Loc ?? "an unknown country"
        let leaked = RegionGate.blocked.contains((report.ipv6Loc ?? "").uppercased()) || (report.loc != nil && report.ipv6Loc != report.loc)
        return FixRow(
            id: .ipv6,
            title: "IPv6",
            detail: "claude.ai sees IPv6 \(report.ipv6IP ?? "") in \(loc).",
            tone: leaked ? .warn : .ok,
            button: leaked ? "Set link-local" : nil,
            action: leaked ? .ipv6LinkLocal : nil
        )
    }

    private static func dns(_ report: MachineReport) -> FixRow {
        let shown = report.nameservers.prefix(4).joined(separator: ", ")
        let detail = shown.isEmpty
            ? "No resolver addresses were read. Flush only clears the cache."
            : "Resolvers in use: \(shown). Flush only clears the cache."
        return FixRow(id: .dns, title: "DNS cache", detail: detail, tone: shown.isEmpty ? .idle : .ok, button: "Flush", action: .flushDNS)
    }

    private static func zone(_ report: MachineReport, previous: String?) -> FixRow {
        if report.timeZone == "Asia/Tokyo" {
            let button = previous == nil ? nil : "Restore \(previous ?? "")"
            return FixRow(id: .zone, title: "Time zone", detail: "This Mac is on Asia/Tokyo.", tone: .ok, button: button, action: previous == nil ? nil : .restoreZone)
        }
        return FixRow(id: .zone, title: "Time zone", detail: "This Mac is on \(report.timeZone).", tone: .idle, button: "Set to Tokyo", action: .setTokyo)
    }

    private static let waiting: [FixRow.ID: FixRow] = Dictionary(uniqueKeysWithValues: FixRow.ID.allCases.map { id in
        (id, FixRow(id: id, title: title(id), detail: "Checking…", tone: .idle, button: nil, action: nil))
    })

    private static func title(_ id: FixRow.ID) -> String {
        switch id {
        case .exit: "Exit IP"
        case .shell: "Shell startup files"
        case .launchctl: "Login environment"
        case .settings: "Claude Code settings"
        case .ipv6: "IPv6"
        case .dns: "DNS cache"
        case .zone: "Time zone"
        }
    }

    static let sample: [FixRow.ID: FixRow] = [
        .exit: FixRow(id: .exit, title: "Exit IP", detail: "93.118.41.99 · JP. This is the IP you pinned.", tone: .ok, button: nil, action: nil),
        .shell: FixRow(id: .shell, title: "Shell startup files", detail: ".zshrc sets HTTPS_PROXY.", tone: .warn, button: "Comment out", action: .cleanShell),
        .launchctl: FixRow(id: .launchctl, title: "Login environment", detail: "No proxy or custom API address is set for apps launched from this login.", tone: .ok, button: nil, action: nil),
        .settings: FixRow(id: .settings, title: "Claude Code settings", detail: "~/.claude/settings.json has ANTHROPIC_BASE_URL.", tone: .warn, button: "Remove", action: .cleanSettings),
        .ipv6: FixRow(id: .ipv6, title: "IPv6", detail: "claude.ai did not answer on IPv6.", tone: .ok, button: nil, action: nil),
        .dns: FixRow(id: .dns, title: "DNS cache", detail: "Resolvers in use: 162.252.172.57, 149.154.159.92. Flush only clears the cache.", tone: .ok, button: "Flush", action: .flushDNS),
        .zone: FixRow(id: .zone, title: "Time zone", detail: "This Mac is on Asia/Hong_Kong.", tone: .idle, button: "Set to Tokyo", action: .setTokyo),
    ]
}
