// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import SwiftUI
import BitbotCore

@main
struct BitbotCopilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var connection = RobotConnection()
    @State private var profiles = ProfileStore()
    @State private var backend = BackendManager()
    @State private var runner = AutoRunner()
    @State private var dataViewer = DataViewerModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(connection)
                .environment(profiles)
                .environment(backend)
                .environment(runner)
                .environment(dataViewer)
                .frame(minWidth: 1000, minHeight: 680)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            AboutCommands()
            CommandGroup(replacing: .newItem) {}
            CommandMenu("机器人") {
                Button("断开连接") { connection.disconnect() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                    .disabled(connection.status == .disconnected)
            }
        }
        Window("关于 Bitbot Copilot", id: "about") {
            AboutView()
        }
        .defaultSize(width: 760, height: 720)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
