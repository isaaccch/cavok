import Foundation

/// Destinations for a local routing-table lookup. These are not connections.
/// `route -n get default` follows the literal `0.0.0.0/0` route. WireGuard-style
/// tunnels often install `0.0.0.0/1` and `128.0.0.0/1` instead, so the literal
/// default can still name `en0` while traffic to the public internet uses `utun`.
public enum RouteQuery {
    public static let ipv4Destination = "1.1.1.1"
    public static let ipv6Destination = "2606:4700:4700::1111"
}

public enum RouteParse {
    public static func interfaceName(in text: String) -> String? {
        for line in text.split(separator: "\n") {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("interface:") else { continue }
            let value = trimmed.dropFirst("interface:".count).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : String(value)
        }
        return nil
    }

    public static func hardwareDevices(in text: String) -> Set<String> {
        var devices: Set<String> = []
        for line in text.split(separator: "\n") {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("Device:") else { continue }
            let value = trimmed.dropFirst("Device:".count).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { devices.insert(String(value)) }
        }
        return devices
    }

    public static func isTunnel(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("utun") || lower.hasPrefix("ipsec") || lower.hasPrefix("ppp") || lower.hasPrefix("wg")
    }

    /// Wi-Fi, Ethernet, and other hardware ports. A tunnel name is never physical.
    public static func isPhysical(_ name: String, hardware: Set<String>) -> Bool {
        if isTunnel(name) { return false }
        if hardware.contains(name) { return true }
        let lower = name.lowercased()
        return lower.hasPrefix("en") || lower.hasPrefix("bridge") || lower.hasPrefix("ap")
    }
}

public enum ProxyParse {
    public static let enableKeys = [
        "HTTPEnable",
        "HTTPSEnable",
        "SOCKSEnable",
        "ProxyAutoConfigEnable",
        "ProxyAutoDiscoveryEnable",
    ]

    public static func enabled(in text: String) -> [String] {
        enableKeys.filter { key in
            guard let regex = try? NSRegularExpression(pattern: "\\b\(key)\\s*:\\s*1\\b") else { return false }
            let range = NSRange(text.startIndex..., in: text)
            return regex.firstMatch(in: text, range: range) != nil
        }
    }
}

public enum IfconfigParse {
    public static func addresses(in text: String, hardware: Set<String>) -> Set<String> {
        var current = ""
        var found: Set<String> = []
        let regex = try? NSRegularExpression(pattern: #"inet6?\s+(\S+)"#)
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if !line.hasPrefix("\t"), !line.hasPrefix(" "), let colon = line.firstIndex(of: ":") {
                current = String(line[..<colon])
                continue
            }
            guard RouteParse.isPhysical(current, hardware: hardware), let regex else { continue }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let valueRange = Range(match.range(at: 1), in: line) else { continue }
            var address = String(line[valueRange])
            if let zone = address.firstIndex(of: "%") { address = String(address[..<zone]) }
            if address == "127.0.0.1" || address == "::1" { continue }
            found.insert(address.lowercased())
        }
        return found
    }
}

public struct SocketLeak: Equatable, Sendable {
    public var pid: String
    public var command: String
    public var localAddress: String

    public init(pid: String, command: String, localAddress: String) {
        self.pid = pid
        self.command = command
        self.localAddress = localAddress
    }
}

public enum SocketAudit {
    /// `lsof -F pcn` records. A leak is an active connection whose local address is on a physical interface.
    public static func leaks(in text: String, physicalIPs: Set<String>) -> [SocketLeak] {
        let physical = Set(physicalIPs.map { $0.lowercased() })
        var pid = ""
        var command = ""
        var found: [SocketLeak] = []
        for raw in text.split(separator: "\n") {
            let line = String(raw)
            guard let kind = line.first else { continue }
            let value = String(line.dropFirst())
            switch kind {
            case "p":
                pid = value
            case "c":
                command = value
            case "n":
                guard let local = localAddress(in: value) else { continue }
                guard physical.contains(local.lowercased()) else { continue }
                found.append(SocketLeak(pid: pid, command: command, localAddress: local))
            default:
                continue
            }
        }
        return found
    }

    static func localAddress(in name: String) -> String? {
        guard let arrow = name.range(of: "->") else { return nil }
        return host(String(name[..<arrow.lowerBound]))
    }

    static func host(_ endpoint: String) -> String {
        if endpoint.hasPrefix("["), let end = endpoint.firstIndex(of: "]") {
            return String(endpoint[endpoint.index(after: endpoint.startIndex)..<end])
        }
        guard let colon = endpoint.lastIndex(of: ":") else { return endpoint }
        return String(endpoint[..<colon])
    }
}

public struct ProtectedProcess: Equatable, Sendable {
    public var pid: Int32
    public var label: String

    public init(pid: Int32, label: String) {
        self.pid = pid
        self.label = label
    }
}

public enum ProcessMatch {
    /// `ps -axo pid=,comm=,args=`. `comm` is 16 bytes, so npm `claude` shows up as `node` and the Codex binary as a truncated `codex-aarch64-ap`. The command line is the match.
    public static func protected(in text: String) -> [ProtectedProcess] {
        var found: [ProtectedProcess] = []
        var seen: Set<Int32> = []
        for raw in text.split(separator: "\n") {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            guard let gap = line.firstIndex(where: { $0.isWhitespace }) else { continue }
            guard let pid = Int32(line[..<gap]) else { continue }
            guard seen.insert(pid).inserted else { continue }
            let command = String(line[gap...])
            guard let label = label(for: command) else { continue }
            found.append(ProtectedProcess(pid: pid, label: label))
        }
        return found
    }

    static func label(for command: String) -> String? {
        if command.contains("Claude.app") { return "Claude" }
        if command.contains("ChatGPT.app") { return "ChatGPT" }
        if matches(command, #"codex(-aarch64[A-Za-z0-9-]*)?"#) { return "codex" }
        if matches(command, #"claude(-code)?"#) { return "claude" }
        return nil
    }

    private static func matches(_ command: String, _ body: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "(^|[/\\s\"])\(body)(\\s|$|\")") else { return false }
        let range = NSRange(command.startIndex..., in: command)
        return regex.firstMatch(in: command, range: range) != nil
    }
}
