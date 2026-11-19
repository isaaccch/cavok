import AppKit
import SwiftUI

enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
}

struct ContentView: View {
    @Environment(FixStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var confirm: Confirm?

    var body: some View {
        NavigationStack {
            Form {
                if store.guardOn {
                    Section {
                        Text(store.packetDropLine)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if store.packetDropNeedsApproval {
                            Button("Open System Settings") { store.openExtensionSettings() }
                        }
                    }
                }
                ForEach(FixStore.sections) { section in
                    Section(section.title) {
                        ForEach(section.ids, id: \.self) { id in
                            if let row = store.rows[id] {
                                FixRowView(row: row, busy: store.busy) {
                                    store.ask(row) { confirm = $0 }
                                }
                            }
                        }
                    }
                }
                if !store.note.isEmpty {
                    Section {
                        Text(store.note)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Cavok")
            .navigationSubtitle("Local fixes only. Surfshark is not changed.")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Clean leftovers") { store.perform(.cleanAll) }
                        .disabled(!store.canClean || store.busy)
                }
                ToolbarItem {
                    Button("Open Claude") { store.perform(.openClaude) }
                        .disabled(!store.canOpen || store.busy)
                        .help(store.openHelp)
                }
                ToolbarItem {
                    Button("Open ChatGPT") { store.perform(.openChatGPT) }
                        .disabled(!store.canOpen || store.busy)
                        .help(store.openHelp)
                }
                ToolbarItem {
                    Button("Check Again") { store.inspect() }
                        .disabled(store.busy)
                }
            }
            .modifier(FixConfirmations(confirm: $confirm))
        }
        .frame(minWidth: 720, minHeight: 640)
        .task {
            CavokActions.openMain = {
                openWindow(id: "main")
                NSApp.activate()
            }
            CavokActions.check = { store.inspect() }
            store.inspectIfNeeded()
        }
    }
}

struct FixConfirmations: ViewModifier {
    @Environment(FixStore.self) private var store
    @Binding var confirm: Confirm?

    func body(content: Content) -> some View {
        content
            .alert("Set IPv6 to link-local?", isPresented: presented(.ipv6)) {
                Button("Set link-local") { store.perform(.ipv6LinkLocal) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Wi-Fi and Ethernet stop using a public IPv6 address. Surfshark is not changed. macOS asks you to approve it.")
            }
            .alert("Set the time zone to Tokyo?", isPresented: presented(.zone)) {
                Button("Set to Tokyo") { store.perform(.setTokyo) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The clock becomes Asia/Tokyo and automatic time zone turns off. Cavok saves the current zone so you can put it back. macOS asks you to approve it.")
            }
            .alert("Turn off system proxies?", isPresented: presented(.proxy)) {
                Button("Turn off") { store.perform(.disableProxy) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("HTTP, HTTPS, SOCKS, and automatic proxy turn off on Wi-Fi and Ethernet. Surfshark is not changed. macOS asks you to approve it.")
            }
    }

    private func presented(_ match: Confirm) -> Binding<Bool> {
        Binding(get: { confirm == match }, set: { if !$0 { confirm = nil } })
    }
}

struct FixRowView: View {
    let row: FixRow
    let busy: Bool
    let act: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Space.lg) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: Space.xl)
                .accessibilityLabel(label)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(row.title)
                Text(row.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.lg)
            if let button = row.button {
                Button(button, action: act)
                    .disabled(busy || row.action == nil)
            }
        }
    }

    private var symbol: String {
        switch row.tone {
        case .ok: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .idle: "circle"
        }
    }

    private var color: Color {
        switch row.tone {
        case .ok: .green
        case .warn: .orange
        case .idle: .secondary
        }
    }

    private var label: String {
        switch row.tone {
        case .ok: "OK"
        case .warn: "Needs a fix"
        case .idle: "Not a problem"
        }
    }
}
