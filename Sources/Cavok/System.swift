import CavokKit
import Foundation

struct Exec: Sendable {
    var stdout = ""
    var stderr = ""
    var code: Int32 = 1
}

struct MachineReport: Sendable {
    var shell: [ShellHit] = []
    var launchctl: [String] = []
    var settingsKeys: [String] = []
    var settingsMissing = false
    var settingsError: String?
    var ip: String?
    var loc: String?
    var traceError: String?
    var ipv6IP: String?
    var ipv6Loc: String?
    var ipv6Blocked = true
    var nameservers: [String] = []
    var timeZone = TimeZone.current.identifier
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

    nonisolated static func curlTrace(ipv6: Bool) -> Exec {
        var args = ["-sS", "--max-time", ipv6 ? "5" : "8", "https://claude.ai/cdn-cgi/trace"]
        args.insert(ipv6 ? "-6" : "-4", at: 0)
        return run("/usr/bin/curl", args)
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
        return admin("""
        /usr/sbin/systemsetup -settimezone \(bashQuote(name))
        /usr/bin/defaults write /Library/Preferences/com.apple.timezone.auto Active -bool \(auto)
        """)
    }

    nonisolated static func admin(_ body: String) -> Exec {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cavok-\(UUID().uuidString).sh")
        let script = "#!/bin/bash\nset -uo pipefail\n\(body)\n"
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        } catch {
            return Exec(stderr: error.localizedDescription, code: 1)
        }
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
            let backup = home.appendingPathComponent(name + ".cavok-bak")
            if FileManager.default.fileExists(atPath: backup.path) {
                try FileManager.default.removeItem(at: backup)
            }
            try FileManager.default.copyItem(at: url, to: backup)
            try Data(edit.text.utf8).write(to: url, options: .atomic)
            let unique = Array(Set(edit.removed)).sorted().joined(separator: ", ")
            notes.append("\(name) (\(unique))")
        }
        return notes.joined(separator: "; ")
    }

    nonisolated static func peekSettings(_ home: URL) -> (missing: Bool, keys: [String], error: String?) {
        let url = home.appendingPathComponent(".claude/settings.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return (true, [], nil) }
        do {
            let data = try Data(contentsOf: url)
            let edit = try SettingsCleaner.cleaning(data)
            return (false, edit.removed, nil)
        } catch {
            return (false, [], "Could not read ~/.claude/settings.json.")
        }
    }

    nonisolated static func cleanSettings(_ home: URL) throws -> String {
        let url = home.appendingPathComponent(".claude/settings.json")
        let data = try Data(contentsOf: url)
        let edit = try SettingsCleaner.cleaning(data)
        guard let written = edit.data else { return "" }
        let backup = home.appendingPathComponent(".claude/settings.json.cavok-bak")
        if FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.removeItem(at: backup)
        }
        try FileManager.default.copyItem(at: url, to: backup)
        try written.write(to: url, options: .atomic)
        return edit.removed.sorted().joined(separator: ", ")
    }
}

enum Machine {
    nonisolated static func inspect(home: URL) async -> MachineReport {
        let shell = HomeFiles.scan(home)
        let settings = HomeFiles.peekSettings(home)
        async let v4 = System.curlTrace(ipv6: false)
        async let v6 = System.curlTrace(ipv6: true)
        async let dns = System.run("/usr/sbin/scutil", ["--dns"])
        async let vars = System.launchctlSet()
        let v4r = await v4
        let v6r = await v6
        let dnsr = await dns
        var report = MachineReport()
        report.shell = shell
        report.launchctl = await vars
        report.settingsMissing = settings.missing
        report.settingsKeys = settings.keys
        report.settingsError = settings.error
        if v4r.code == 0 {
            report.ip = TraceParse.field("ip", in: v4r.stdout)
            report.loc = TraceParse.field("loc", in: v4r.stdout)
            if report.ip == nil { report.traceError = "claude.ai answered without an IP." }
        } else {
            let reason = v4r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            report.traceError = reason.isEmpty ? "Could not reach claude.ai." : reason
        }
        if v6r.code == 0, let ip = TraceParse.field("ip", in: v6r.stdout) {
            report.ipv6Blocked = false
            report.ipv6IP = ip
            report.ipv6Loc = TraceParse.field("loc", in: v6r.stdout)
        } else {
            report.ipv6Blocked = true
        }
        report.nameservers = DNSParse.nameservers(in: dnsr.stdout)
        report.timeZone = TimeZone.current.identifier
        return report
    }
}
