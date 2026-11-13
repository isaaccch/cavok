import AppKit

enum CheckDump {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["APP_CHECK"] == "1" else { return }
        Task {
            let report = await Machine.inspect(home: FileManager.default.homeDirectoryForCurrentUser)
            print("CHECK route=\(report.routeInterface ?? "-") tunnel=\(report.routeIsTunnel) physical=\(report.routeIsPhysical) skipped=\(report.traceSkipped)")
            print("CHECK ip=\(report.ip ?? "-") loc=\(report.loc ?? "-")")
            print("CHECK chatgpt=\(report.chatgptIP ?? "-") loc=\(report.chatgptLoc ?? "-") error=\(report.chatgptError ?? "-")")
            print("CHECK shell=\(report.shell.map { "\($0.file):\($0.name)" }.joined(separator: ","))")
            print("CHECK launchctl=\(report.launchctl.joined(separator: ","))")
            print("CHECK configs=\(report.configHits.map { "\($0.file):\($0.keys.joined(separator: "+"))" }.joined(separator: ","))")
            print("CHECK codex=\(report.codexKeys.joined(separator: ",")) missing=\(report.codexMissing) error=\(report.codexError ?? "-")")
            print("CHECK proxy=\(report.proxyEnabled.joined(separator: ","))")
            print("CHECK sockets=\(report.socketLeaks.map { "\($0.pid):\($0.localAddress)" }.joined(separator: ","))")
            print("CHECK ipv6Missing=\(report.ipv6Missing) skipped=\(report.ipv6Skipped) claude=\(report.ipv6Claude.ip ?? "-") \(report.ipv6Claude.loc ?? "-") chatgpt=\(report.ipv6ChatGPT.ip ?? "-") \(report.ipv6ChatGPT.loc ?? "-")")
            print("CHECK dns=\(report.nameservers.prefix(4).joined(separator: ","))")
            print("CHECK zone=\(report.timeZone)")
            print("CHECK traceError=\(report.traceError ?? "-")")
            NSApp.terminate(nil)
        }
    }
}

enum Snapshot {
    static func runIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["APP_SNAPSHOT"], !dir.isEmpty else { return }
        Task {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(1))
            let menu = ProcessInfo.processInfo.environment["APP_SNAPSHOT_MENU"] != nil
            let name = menu ? "menubar" : "fixes"
            for mode in ["light", "dark"] {
                NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                try? await Task.sleep(for: .milliseconds(800))
                capture(title: "Cavok", to: "\(dir)/\(name)-\(mode).png")
            }
            print("SNAPSHOT done \(dir)")
            NSApp.terminate(nil)
        }
    }

    private static func capture(title: String, to path: String) {
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window = NSApp.windows.first(where: { $0.title == title && $0.canBecomeMain && !$0.isSheet }) else {
            print("SNAPSHOT no window \(title)")
            return
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        try? FileManager.default.removeItem(atPath: path)
        for _ in 1...3 {
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try? shot.run()
            shot.waitUntilExit()
            if FileManager.default.fileExists(atPath: path) {
                print("SNAPSHOT \(path)")
                return
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) (fallback)")
        }
    }
}
