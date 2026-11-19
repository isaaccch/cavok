import AppKit
import CavokKit
import SwiftUI

struct MenuBarView: View {
    @Environment(FixStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var confirm: Confirm?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    ForEach(FixStore.sections) { section in
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(section.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                        Text(store.note)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Space.lg)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 420)
            Divider()
            VStack(alignment: .leading, spacing: Space.sm) {
                Toggle("Guard", isOn: Binding(get: { store.guardOn }, set: { store.setGuard($0) }))
                    .help("Quit Claude, ChatGPT, claude, and codex when the route, either exit, a pin, a socket on Wi-Fi or Ethernet, a leftover, or IPv6 is blocked, and when the Mac sleeps. A timeout does not.")
                if store.guardOn {
                    Text(store.packetDropLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: Space.sm) {
                    Button("Check Again") { store.inspect() }
                        .disabled(store.busy)
                    Button("Clean leftovers") { store.perform(.cleanAll) }
                        .disabled(!store.canClean || store.busy)
                    Spacer(minLength: 0)
                }
                HStack(spacing: Space.sm) {
                    Button("Open Claude") { store.perform(.openClaude) }
                        .disabled(!store.canOpen || store.busy)
                        .help(store.openHelp)
                    Button("Open ChatGPT") { store.perform(.openChatGPT) }
                        .disabled(!store.canOpen || store.busy)
                        .help(store.openHelp)
                    Spacer(minLength: 0)
                }
                HStack(spacing: Space.sm) {
                    Button("Open Window") { showWindow() }
                    Spacer(minLength: 0)
                    Button("Quit") { NSApp.terminate(nil) }
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 380)
        .modifier(FixConfirmations(confirm: $confirm))
        .task {
            CavokActions.openMain = { showWindow() }
            CavokActions.check = { store.inspect() }
            store.inspectIfNeeded()
        }
    }

    private func showWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }
}

struct MenuBarSettings: View {
    @Environment(FixStore.self) private var store
    @AppStorage("showMenuBar") private var showMenuBar = true

    var body: some View {
        Form {
            Section {
                Toggle("Show Cavok in the menu bar", isOn: $showMenuBar)
                Toggle("Guard", isOn: Binding(get: { store.guardOn }, set: { store.setGuard($0) }))
                if store.guardOn {
                    Text(store.packetDropLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Guard quits Claude, ChatGPT, claude, and codex when the route leaves the tunnel, either exit is HK, CN, or MO, the two exits differ, a pinned IP does not match, a proxy or custom API address is still set, a Claude or ChatGPT connection is on Wi-Fi or Ethernet, or IPv6 leaks. Sleep quits them too. Another Japan IP fails the pin. A timeout, the time zone, a curl challenge, or DNS does not quit anything.")
            }
            Section {
                if store.workspacePaths.isEmpty {
                    Text("No folders yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.workspacePaths, id: \.self) { path in
                    HStack {
                        Text(PathDisplay.abbreviate(path))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: Space.sm)
                        Button("Remove") { store.removeRoot(path) }
                    }
                }
                Button("Add Folder…") { store.pickRoot() }
            } header: {
                Text("Project folders")
            } footer: {
                Text("Cavok looks a few levels down for .claude/settings.json and settings.local.json. Projects and Developer are added when those folders exist. Add Desktop yourself.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}
