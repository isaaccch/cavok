import AppKit
import CavokKit
import Foundation
import Network

@MainActor
final class Watchdog {
    private weak var store: FixStore?
    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "cavok.watchdog")
    private var debounce: Task<Void, Never>?
    private var killLoop: Task<Void, Never>?
    private var sawFirstPath = false
    private var sleepObserver: NSObjectProtocol?
    private var launchObserver: NSObjectProtocol?

    init(store: FixStore) {
        self.store = store
    }

    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in
                self?.onPathUpdate()
            }
        }
        monitor.start(queue: queue)
        self.monitor = monitor

        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.onSleep()
            }
        }
        launchObserver = center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let path = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleURL?.path ?? ""
            guard path.contains("Claude.app") || path.contains("ChatGPT.app") else { return }
            Task { @MainActor in
                self?.onProtectedLaunch()
            }
        }
    }

    func refresh() {
        let shouldRun = store?.guardOn == true && store?.blockingReason != nil
        if shouldRun {
            guard killLoop == nil else { return }
            killLoop = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, let store = self.store, store.guardOn, store.blockingReason != nil else { break }
                    System.terminateProtected(force: true)
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
        debounce?.cancel()
        Task.detached {
            let route = System.routeLookup(RouteQuery.ipv4Destination)
            let ports = System.run("/usr/sbin/networksetup", ["-listallhardwareports"])
            let hardware = RouteParse.hardwareDevices(in: ports.stdout)
            let interface = route.code == 0 ? RouteParse.interfaceName(in: route.stdout) : nil
            let physical = interface.map { RouteParse.isPhysical($0, hardware: hardware) } ?? false
            await MainActor.run { [weak self] in
                self?.handle(interface: interface, physical: physical)
            }
        }
    }

    private func handle(interface: String?, physical: Bool) {
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
        scheduleInspect()
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

    private func onProtectedLaunch() {
        guard let store, store.guardOn, store.blockingReason != nil else { return }
        let labels = System.terminateProtected(force: true)
        store.note = "Guard quit \(Self.list(labels.isEmpty ? ["Claude"] : labels)). The exit is blocked."
    }

    private static func list(_ labels: [String]) -> String {
        labels.sorted().joined(separator: ", ")
    }
}
