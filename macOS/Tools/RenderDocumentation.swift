// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import AppKit
import SwiftUI
import BitbotCore

/// Renders the actual native views offscreen using synthetic CSV data.
/// No robot connections or user profiles are opened during documentation generation.
@main
struct RenderDocumentation {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fatalError("Usage: render-docs <repository> <output-directory>")
        }
        let repository = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .aqua)
        let profiles = ProfileStore(directory: temporary)
        let model = DataViewerModel()
        let csv = try CSVData(text: String(contentsOf: repository.appendingPathComponent("doc/examples/demo-telemetry.csv")))
        model.csv = csv
        model.samples = csv.rows.enumerated().map { Sample(id: $0.offset, time: Double($0.offset), values: $0.element) }
        model.selected = [1, 2, 3]; model.xColumn = 0; model.filename = "demo-telemetry.csv"

        for (page, name) in [(Page.home, "home.png"), (.data, "data-viewer.png")] {
            let root = ContentView(initialPage: page)
                .environment(RobotConnection()).environment(profiles)
                .environment(BackendManager()).environment(AutoRunner()).environment(model)
                .environment(\.colorScheme, .light)
                .frame(width: 1280, height: 820)
                .background(Color(nsColor: .windowBackgroundColor))
            let host = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                                  styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.setFrameSize(NSSize(width: 1280, height: 820))
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                fatalError("Could not allocate a documentation bitmap")
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                fatalError("Could not encode documentation image")
            }
            try png.write(to: output.appendingPathComponent(name))
            window.contentView = nil
            window.close()
            print("Rendered \(name)")
        }
    }
}
