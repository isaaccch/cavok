import AppKit
import SwiftUI

@MainActor
enum CavokActions {
    static var openMain: (() -> Void)?
    static var check: (() -> Void)?
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let show = NSMenuItem(title: "Show Cavok", action: #selector(showCavok), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let check = NSMenuItem(title: "Check Again", action: #selector(checkAgain), keyEquivalent: "")
        check.target = self
        menu.addItem(check)
        return menu
    }

    @objc func showCavok() { CavokActions.openMain?() }
    @objc func checkAgain() { CavokActions.check?() }
}

@main
struct CavokApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = FixStore()
    @AppStorage("showMenuBar") private var showMenuBar = true

    var body: some Scene {
        Window("Cavok", id: "main") {
            Group {
                if ProcessInfo.processInfo.environment["APP_SNAPSHOT_MENU"] != nil {
                    MenuBarView()
                } else {
                    ContentView()
                }
            }
            .environment(store)
            .onAppear {
                CheckDump.runIfRequested()
                Snapshot.runIfRequested()
            }
        }
        .defaultSize(
            width: ProcessInfo.processInfo.environment["APP_SNAPSHOT_MENU"] != nil ? 360 : 760,
            height: ProcessInfo.processInfo.environment["APP_SNAPSHOT_MENU"] != nil ? 720 : 700
        )
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Check Again") {
                    if !store.busy { store.inspect() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.busy)
            }
        }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarView()
                .environment(store)
        } label: {
            Label(store.menuTitle, systemImage: store.menuSymbol)
                .labelStyle(.titleAndIcon)
        }
        .menuBarExtraStyle(.window)

        Settings {
            MenuBarSettings()
                .environment(store)
        }
    }
}
