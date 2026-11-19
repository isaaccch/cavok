import Foundation

/// Names a leftover proxy or a custom API host. Values are never returned.
public enum LeftoverName {
    public static let shell: Set<String> = [
        "ANTHROPIC_BASE_URL",
        "OPENAI_BASE_URL",
        "OPENAI_API_BASE",
        "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY",
        "http_proxy", "https_proxy", "all_proxy",
    ]

    public static let launchctl: [String] = [
        "http_proxy", "https_proxy", "all_proxy",
        "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY",
        "ANTHROPIC_BASE_URL", "OPENAI_BASE_URL", "OPENAI_API_BASE",
    ]

    public static let proxyKeys: Set<String> = [
        "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY",
        "http_proxy", "https_proxy", "all_proxy",
    ]

    public static let officialHosts: Set<String> = [
        "api.anthropic.com",
        "api.openai.com",
    ]

    public static let baseURLKeys: Set<String> = [
        "ANTHROPIC_BASE_URL",
        "OPENAI_BASE_URL",
        "OPENAI_API_BASE",
    ]

    public static let tokenKeys: Set<String> = [
        "ANTHROPIC_AUTH_TOKEN",
        "OPENAI_API_KEY",
    ]

    /// `NO_PROXY` is a bypass list, not a relay.
    public static func isProxyKey(_ key: String) -> Bool {
        let upper = key.uppercased()
        if upper == "NO_PROXY" { return false }
        return upper.hasSuffix("_PROXY")
    }

    /// Official API hosts, including OpenAI data-residency subdomains such as `us.api.openai.com`.
    public static func isOfficialAPI(_ value: String) -> Bool {
        var raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.count >= 2, let first = raw.first, let last = raw.last, (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            raw = String(raw.dropFirst().dropLast())
        }
        if !raw.contains("://") { raw = "https://" + raw }
        guard let host = URL(string: raw)?.host?.lowercased() else { return false }
        if officialHosts.contains(host) { return true }
        if host == "anthropic.com" || host.hasSuffix(".anthropic.com") { return true }
        if host == "openai.com" || host.hasSuffix(".openai.com") { return true }
        if host == "chatgpt.com" || host.hasSuffix(".chatgpt.com") { return true }
        return false
    }
}

public struct ShellHit: Equatable, Sendable {
    public var file: String
    public var name: String

    public init(file: String, name: String) {
        self.file = file
        self.name = name
    }
}

public struct ShellEdit: Equatable, Sendable {
    public var text: String
    public var removed: [String]

    public init(text: String, removed: [String]) {
        self.text = text
        self.removed = removed
    }
}

public enum ShellCleaner {
    /// Startup files, in the order a login shell would care about them.
    public static let fileNames = [
        ".zshenv", ".zprofile", ".zshrc",
        ".bash_profile", ".bashrc", ".profile",
    ]

    public static func commenting(_ text: String, date: String) -> ShellEdit {
        var removed: [String] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let edited = lines.map { line -> String in
            guard let name = assignedName(in: line) ?? launchctlName(in: line) else { return line }
            guard LeftoverName.shell.contains(name) else { return line }
            removed.append(name)
            return "# cavok \(date): commented out \(name)\n# \(line)"
        }
        let joined = edited.joined(separator: "\n")
        let restoredNewline = text.hasSuffix("\n") && !joined.hasSuffix("\n") ? joined + "\n" : joined
        return ShellEdit(text: restoredNewline, removed: removed)
    }

    public static func hits(in text: String, file: String) -> [ShellHit] {
        text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { raw in
            let line = String(raw)
            guard let name = assignedName(in: line) ?? launchctlName(in: line) else { return nil }
            guard LeftoverName.shell.contains(name) else { return nil }
            return ShellHit(file: file, name: name)
        }
    }

    static func assignedName(in line: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*="#
        ) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let nameRange = Range(match.range(at: 1), in: line) else { return nil }
        return String(line[nameRange])
    }

    static func launchctlName(in line: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"^\s*(?:sudo\s+)?launchctl\s+setenv\s+([A-Za-z_][A-Za-z0-9_]*)\b"#
        ) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let nameRange = Range(match.range(at: 1), in: line) else { return nil }
        return String(line[nameRange])
    }
}

public struct SettingsEdit: Equatable, Sendable {
    public var removed: [String]
    public var data: Data?

    public init(removed: [String], data: Data?) {
        self.removed = removed
        self.data = data
    }
}

public enum SettingsCleaner {
    /// Removes relay and proxy keys from the `env` object. Other keys stay.
    /// A token is removed only when the same `env` object points the API at a host that is not Anthropic or OpenAI.
    public static func cleaning(_ data: Data) throws -> SettingsEdit {
        let root = try JSONSerialization.jsonObject(with: data)
        guard var object = root as? [String: Any] else {
            throw CleanError.notAnObject
        }
        guard var env = object["env"] as? [String: Any] else {
            return SettingsEdit(removed: [], data: nil)
        }

        var removed: [String] = []
        let relay = env.keys.contains { key in
            guard LeftoverName.baseURLKeys.contains(key) else { return false }
            return relayHost(env[key])
        }

        for key in env.keys.sorted() {
            let dropProxy = LeftoverName.isProxyKey(key)
            let dropRelayURL = LeftoverName.baseURLKeys.contains(key) && relayHost(env[key])
            let dropToken = relay && LeftoverName.tokenKeys.contains(key)
            if dropProxy || dropRelayURL || dropToken {
                env.removeValue(forKey: key)
                removed.append(key)
            }
        }

        guard !removed.isEmpty else { return SettingsEdit(removed: [], data: nil) }
        if env.isEmpty {
            object.removeValue(forKey: "env")
        } else {
            object["env"] = env
        }
        let written = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        return SettingsEdit(removed: removed, data: written)
    }

    static func relayHost(_ value: Any?) -> Bool {
        guard let value = value as? String else { return true }
        return !isOfficial(value)
    }

    static func isOfficial(_ value: String) -> Bool {
        LeftoverName.isOfficialAPI(value)
    }
}

public enum CleanError: Error, Equatable {
    case notAnObject
}

public enum TraceParse {
    public static func field(_ name: String, in text: String) -> String? {
        for line in text.split(separator: "\n") {
            let raw = String(line)
            let prefix = name + "="
            if raw.hasPrefix(prefix) {
                let value = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    /// The address curl connected to, written by `-w remote=%{remote_ip}`.
    public static func remoteAddress(in text: String) -> String? {
        guard let value = field("remote", in: text), value != "0.0.0.0", PacketDrop.isIPLiteral(value) else {
            return nil
        }
        return value
    }
}

public enum ServiceList {
    /// Network services Cavok may change. Disabled rows and Surfshark tunnels are left alone.
    public static func changeable(from raw: String) -> [String] {
        raw.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().compactMap { piece in
            let line = String(piece).trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("*") { return nil }
            if line.localizedCaseInsensitiveContains("surfshark") { return nil }
            return line
        }
    }
}

public enum DNSParse {
    public static func nameservers(in text: String) -> [String] {
        let body = head(text)
        return unique(in: body, pattern: #"nameserver\[\d+\]\s*:\s*(\S+)"#)
    }

    /// `if_index : 12 (utun4)` from the primary resolvers. Scoped queries are left out.
    public static func interfaces(in text: String) -> [String] {
        unique(in: head(text), pattern: #"if_index\s*:\s*\d+\s*\(([^)]+)\)"#)
    }

    static func head(_ text: String) -> String {
        if let scoped = text.range(of: "DNS configuration (for scoped queries)") {
            return String(text[..<scoped.lowerBound])
        }
        return text
    }

    private static func unique(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen: [String] = []
        for match in regex.matches(in: text, range: range) {
            guard let valueRange = Range(match.range(at: 1), in: text) else { continue }
            let value = String(text[valueRange])
            if !seen.contains(value) { seen.append(value) }
        }
        return seen
    }
}

public enum RegionGate {
    public static let blocked: Set<String> = ["HK", "CN", "MO"]

    public static func allows(_ loc: String?) -> Bool {
        guard let loc, !loc.isEmpty else { return false }
        return !blocked.contains(loc.uppercased())
    }
}

public struct IPv6HostResult: Equatable, Sendable {
    public var host: String
    public var ip: String?
    public var loc: String?

    public init(host: String, ip: String? = nil, loc: String? = nil) {
        self.host = host
        self.ip = ip
        self.loc = loc
    }
}

public enum IPv6Trace {
    /// An `ip=` with no colon, or one that contains `::ffff:`, is not an IPv6 result.
    public static func result(host: String, trace: String) -> IPv6HostResult {
        guard let ip = realAddress(TraceParse.field("ip", in: trace)) else {
            return IPv6HostResult(host: host)
        }
        return IPv6HostResult(host: host, ip: ip, loc: TraceParse.field("loc", in: trace))
    }

    public static func realAddress(_ value: String?) -> String? {
        guard let value, value.contains(":"), !value.lowercased().contains("::ffff:") else { return nil }
        return value
    }
}

public struct PageHeaders: Equatable, Sendable {
    public var status: Int?
    public var mitigated: Bool
    public var challenged: Bool

    public init(status: Int? = nil, mitigated: Bool = false, challenged: Bool = false) {
        self.status = status
        self.mitigated = mitigated
        self.challenged = challenged
    }
}

public enum ReachParse {
    /// Last HTTP status, plus whether any hop was `cf-mitigated` or status 403 or 421.
    public static func parse(_ headers: String) -> PageHeaders {
        var last: Int?
        var mitigated = false
        var challenged = false
        for raw in headers.split(whereSeparator: \.isNewline) {
            let line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = line.lowercased()
            if lower.hasPrefix("http/") {
                let parts = line.split(separator: " ")
                if parts.count >= 2, let code = Int(parts[1]) {
                    last = code
                    if code == 403 || code == 421 { challenged = true }
                }
            } else if lower.hasPrefix("cf-mitigated:") {
                mitigated = true
                challenged = true
            }
        }
        return PageHeaders(status: last, mitigated: mitigated, challenged: challenged)
    }

    public static func challengedHosts(claude: String, chatgpt: String) -> [String] {
        var hosts: [String] = []
        if parse(claude).challenged { hosts.append("claude.ai") }
        if parse(chatgpt).challenged { hosts.append("chatgpt.com") }
        return hosts
    }
}

public struct LocaleTag: Equatable, Sendable {
    public var source: String
    public var region: String

    public init(source: String, region: String) {
        self.source = source
        self.region = region
    }
}

public enum LocaleTags {
    /// HK, CN, and MO tags in the three local preference values. Simplified Chinese input is CN. Traditional Chinese input is HK.
    public static func find(locale: String, languages: [String], inputSources: String) -> [LocaleTag] {
        var tags: [LocaleTag] = []
        func add(_ source: String, _ region: String) {
            let code = region.uppercased()
            guard RegionGate.blocked.contains(code) else { return }
            let tag = LocaleTag(source: source, region: code)
            if !tags.contains(tag) { tags.append(tag) }
        }
        for region in regions(in: locale) { add("AppleLocale", region) }
        for language in languages {
            for region in regions(in: language) { add("AppleLanguages", region) }
        }
        for region in regions(in: inputSources) { add("AppleEnabledInputSources", region) }
        let modes = inputSources.lowercased()
        if modes.contains("com.apple.inputmethod.scim") { add("AppleEnabledInputSources", "CN") }
        if modes.contains("com.apple.inputmethod.tcim") { add("AppleEnabledInputSources", "HK") }
        return tags
    }

    /// Tag regions that are not the country of every exit. No exits means no mismatch.
    public static func regionsThatDiffer(_ tags: [LocaleTag], from exits: [String]) -> [String] {
        let known = exits.map { $0.uppercased() }.filter { !$0.isEmpty }
        guard !known.isEmpty else { return [] }
        var found: [String] = []
        for tag in tags {
            let differs = known.contains { $0 != tag.region }
            if differs, !found.contains(tag.region) { found.append(tag.region) }
        }
        return found
    }

    static func regions(in text: String) -> [String] {
        var found: [String] = []
        func take(_ pattern: String) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                guard let valueRange = Range(match.range(at: 1), in: text) else { continue }
                let code = String(text[valueRange]).uppercased()
                if RegionGate.blocked.contains(code), !found.contains(code) { found.append(code) }
            }
        }
        take(#"(?i)(?:^|[^A-Za-z])(hk|cn|mo)(?=[^A-Za-z]|$)"#)
        take(#"(?i)@rg=(hk|cn|mo)"#)
        return found
    }
}

public enum BackupFile {
    /// Create `.cavok-bak` only when that file is absent. Never replace one.
    public static func shouldCreate(backupExists: Bool) -> Bool {
        !backupExists
    }
}
