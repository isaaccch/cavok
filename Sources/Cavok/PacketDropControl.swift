import CavokKit
import Foundation
@preconcurrency import NetworkExtension
import SystemExtensions

extension Notification.Name {
    static let packetDropArmed = Notification.Name("cavok.packetDropArmed")
}

enum PacketDropState: Equatable {
    case off
    case armed
    case notBundled
    case needsApproval
    case failed(String)
}

@MainActor
final class PacketDropControl: NSObject, OSSystemExtensionRequestDelegate {
    static let extensionIdentifier = "com.isaaccheung.cavok.guard"

    private var state: PacketDropState = .off
    private var generation = 0
    private var readyToken: Int32 = 0
    private var blockedToken: Int32 = 0
    var onChange: ((PacketDropState) -> Void)?

    override init() {
        super.init()
        readyToken = CavokNotify.listen(PacketDropNote.ready) { [weak self] _ in
            Task { @MainActor in self?.setState(.armed) }
        }
        blockedToken = CavokNotify.listen(PacketDropNote.blocked) { [weak self] _ in
            Task { @MainActor in self?.setState(.failed("The filter stopped.")) }
        }
    }

    deinit {
        let ready = readyToken
        let blocked = blockedToken
        if ready != 0 { CavokNotify.cancel(ready) }
        if blocked != 0 { CavokNotify.cancel(blocked) }
    }

    func setEnabled(_ on: Bool) {
        generation += 1
        let generation = generation
        guard on else {
            save(enabled: false, generation: generation)
            return
        }
        guard extensionIsBundled else {
            setState(.notBundled)
            return
        }
        CavokNotify.post(PacketDropNote.check)
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: Self.extensionIdentifier,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension replacement: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        setState(.needsApproval)
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        guard result == .completed else {
            setState(.failed("The extension did not finish activating."))
            return
        }
        save(enabled: true, generation: generation)
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        setState(.failed(error.localizedDescription))
    }

    private var extensionIsBundled: Bool {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/SystemExtensions/\(Self.extensionIdentifier).systemextension")
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func save(enabled: Bool, generation: Int) {
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { [weak self] error in
            guard let self else { return }
            if error != nil {
                Task { @MainActor in
                    guard generation == self.generation else { return }
                    self.setState(.failed(error?.localizedDescription ?? "The filter settings could not be loaded."))
                }
                return
            }
            let configuration = NEFilterProviderConfiguration()
            configuration.filterSockets = true
            configuration.filterPackets = false
            manager.providerConfiguration = configuration
            manager.localizedDescription = "Cavok packet drop"
            manager.isEnabled = enabled
            manager.saveToPreferences { error in
                Task { @MainActor in
                    guard generation == self.generation else { return }
                    if let error {
                        self.setState(.failed(error.localizedDescription))
                        return
                    }
                    if enabled {
                        self.reloadLater(generation: generation)
                        CavokNotify.post(PacketDropNote.check)
                    } else {
                        self.setState(.off)
                    }
                }
            }
        }
    }

    private func reloadLater(generation: Int) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self, generation == self.generation else { return }
            let current = NEFilterManager.shared()
            current.loadFromPreferences { [weak self] error in
                let enabled = error == nil && NEFilterManager.shared().isEnabled
                Task { @MainActor in
                    guard let self, generation == self.generation else { return }
                    if !enabled { self.setState(.failed("The filter is not enabled in System Settings.")) }
                }
            }
        }
    }

    private func setState(_ next: PacketDropState) {
        guard state != next else { return }
        state = next
        onChange?(next)
    }
}
