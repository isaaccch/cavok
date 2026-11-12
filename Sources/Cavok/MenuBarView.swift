import AppKit
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
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: 560)
            Divider()
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(spacing: Space.sm) {
                    Button("Check Again") { store.inspect() }
                        .disabled(store.busy)
                    Button("Clean leftovers") { store.perform(.cleanAll) }
                        .disabled(!store.canClean || store.busy)
                    Spacer(minLength: 0)
                }
                HStack(spacing: Space.sm) {
                    Button("Open Claude") { store.perform(.openClaude) }
                        .disabled(!store.canOpenClaude || store.busy)
                    Button("Open Window") { showWindow() }
                    Spacer(minLength: 0)
                    Button("Quit") { NSApp.terminate(nil) }
                }
            }
            .padding(Space.lg)
        }
        .frame(width: 360)
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
    @AppStorage("showMenuBar") private var showMenuBar = true

    var body: some View {
        Form {
            Section {
                Toggle("Show Cavok in the menu bar", isOn: $showMenuBar)
                    .controlSize(.mini)
            } footer: {
                Text("Closing the window leaves the menu bar icon in place.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
    }
}
