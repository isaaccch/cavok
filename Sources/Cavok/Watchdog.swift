import AppKit
import CavokKit
import Foundation
import Network

@MainActor
final class Watchdog {
    private weak var store: FixStore?
    private var monitor: NWPathMonitor?
    private var routes: RouteEvents?
    private let queue = DispatchQueue(label: "cavok.watchdog")
    private var debounce: Task<Void, Never>?
    private var killLoop: Task<Void, Never>?
    private var recheckLoop: Task<Void, Never>?
    private var sawFirstPath = false
    private var routeReadInFlight = false
    private var routeReadAgain = false
    private var routeReadResetsInspect = false
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var launchObserver: NSObjectProtocol?

    init(store: FixStore) {
        self.store = store
    }

    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { @Sendable [weak self] _ in
            Task { @MainActor in
                self?.onPathUpdate()
            }
        }
        monitor.start(queue: queue)
        self.monitor = monitor

        let routes = RouteEvents { @Sendable [weak self] in
            Task { @MainActor in
                self?.readRoute(resetsInspect: false)
            }
        }
        routes.start()
        self.routes = routes

        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.onSleep()
            }
        }
        wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.onWake()
            }
        }
        launchObserver = center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let path = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleURL?.path ?? ""
            guard path.contains("Claude.app") || path.contains("ChatGPT.app") else { return }
            Task { @MainActor in
                self?.onProtectedLaunch()
            }
        }
        startRecheck()
    }

    func refresh() {
        let shouldRun = store?.guardOn == true && store?.blockingReason != nil
        if shouldRun {
            guard killLoop == nil else { return }
            killLoop = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard let self, let store = self.store, store.guardOn, store.blockingReason != nil else { break }
                    _ = await Task.detached {
                        System.terminateProtected(force: true)
                    }.value
                }
                self?.killLoop = nil
            }
        } else {
            killLoop?.cancel()
            killLoop = nil
        }
    }

    private func onPathUpdate() {
        guard sawFirstPath else {
            sawFirstPath = true
            return
        }
        readRoute(resetsInspect: true)
    }

    /// One in-process lookup for `1.1.1.1`. A second wake during that lookup runs again after it.
    /// A routing-socket wake does not reset the 2.5 second settle. A path change does.
    private func readRoute(resetsInspect: Bool) {
        if resetsInspect {
            debounce?.cancel()
            routeReadResetsInspect = true
        }
        if routeReadInFlight {
            routeReadAgain = true
            return
        }
        routeReadInFlight = true
        Task.detached {
            let probe = RouteSocket.publicRoute()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.routeReadInFlight = false
                let again = self.routeReadAgain
                let reset = self.routeReadResetsInspect
                self.routeReadAgain = false
                self.routeReadResetsInspect = false
                self.handle(interface: probe.interface, physical: probe.physical, resetsInspect: reset)
                if again { self.readRoute(resetsInspect: false) }
            }
        }
    }

    private func handle(interface: String?, physical: Bool, resetsInspect: Bool) {
        guard let store else { return }
        if physical && store.guardOn {
            let labels = System.terminateProtected(force: true)
            let name = interface ?? "Wi-Fi"
            store.note = labels.isEmpty
                ? "Route left the tunnel (\(name))."
                : "Guard quit \(Self.list(labels)). Route left the tunnel (\(name))."
            store.inspect(keepNote: true)
            return
        }
        if resetsInspect { scheduleInspect() }
    }

    private func scheduleInspect() {
        debounce?.cancel()
        debounce = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(2500))
            guard !Task.isCancelled else { return }
            self?.store?.inspect()
        }
    }

    private func onSleep() {
        guard let store, store.guardOn else { return }
        let labels = System.terminateProtected(force: false)
        guard !labels.isEmpty else { return }
        store.note = "Guard quit \(Self.list(labels)) before sleep."
    }

    /// A full check after the tunnel has had a moment to return. A path change resets this wait.
    private func onWake() {
        scheduleInspect()
    }

    /// `CAVOK_RECHECK_SECONDS` shortens the wait. The loop only notices a change. `inspect` decides.
    private func startRecheck() {
        guard recheckLoop == nil else { return }
        recheckLoop = Task { @MainActor [weak self] in
            var quiet = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.recheckEvery)
                guard !Task.isCancelled, let self, let store = self.store else { break }
                guard !store.busy, store.routeIsTunnel else { continue }
                let seen = await Machine.traceExits()
                guard !Task.isCancelled, !store.busy else { continue }
                if store.exitDrifted(seen) {
                    quiet = 0
                    store.inspect()
                } else if store.exitWentQuiet(seen) {
                    quiet += 1
                    guard quiet >= 2 else { continue }
                    quiet = 0
                    store.inspect()
                } else {
                    quiet = 0
                }
            }
            self?.recheckLoop = nil
        }
    }

    private static var recheckEvery: Duration {
        if let raw = ProcessInfo.processInfo.environment["CAVOK_RECHECK_SECONDS"],
           let seconds = Double(raw), seconds > 0 {
            return .seconds(seconds)
        }
        return .seconds(60)
    }

    private func onProtectedLaunch() {
        guard let store, store.guardOn, store.blockingReason != nil else { return }
        let labels = System.terminateProtected(force: true)
        store.note = "Guard quit \(Self.list(labels.isEmpty ? ["Claude", "ChatGPT"] : labels)). The check is blocked."
    }

    private static func list(_ labels: [String]) -> String {
        labels.sorted().joined(separator: ", ")
    }
}
