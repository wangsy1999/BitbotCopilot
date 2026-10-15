// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import AppKit
import XCTest
import BitbotCore
@testable import BitbotCopilot

final class InputResumeTests: XCTestCase {
    @MainActor func testPollingResumesAfterAppSwitchAndSendsKeyboardEvents() async throws {
        _ = NSApplication.shared
        let server = try await InputTestRobot()
        defer { server.stop() }
        let connection = RobotConnection()
        defer { connection.disconnect() }
        connection.connect(host: "127.0.0.1", port: server.port)
        try await eventually { connection.isConnected }

        var active = true
        let input = InputController(applicationIsActive: { active })
        input.start(connection)
        defer { input.stop() }
        XCTAssertTrue(input.enabled)
        let down = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13))
        let up = try XCTUnwrap(NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13))
        XCTAssertTrue(input.keyboard(down))
        try await eventually { connection.controlFeedback["walk"]?.phase == .pressed }

        // No SwiftUI scene callback: polling must release and later resume on its own.
        active = false
        try await eventually { !input.enabled && connection.controlFeedback["walk"]?.phase == .released }
        XCTAssertTrue(input.activeKeys.isEmpty)
        XCTAssertFalse(input.keyboard(down))
        active = true
        try await eventually { input.enabled }
        XCTAssertTrue(input.keyboard(down))
        try await eventually { connection.controlFeedback["walk"]?.phase == .pressed }
        XCTAssertTrue(input.keyboard(up))
        try await eventually { connection.controlFeedback["walk"]?.phase == .released }

        // Foregrounding must never restart an input controller for a page that was left.
        input.stop()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(input.enabled)
        XCTAssertFalse(input.keyboard(down))
    }

    @MainActor private func eventually(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            guard Date() < deadline else { XCTFail("Timed out waiting for input transition"); throw BitbotError.invalid("Test timeout") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

private final class InputTestRobot {
    let process = Process()
    let ready = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var port = 0

    init() async throws {
        // Reuse the repository's wire-protocol fixture without keeping a second copy.
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("BitbotCoreTests/Fixtures/robot_server.py")
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [fixture.path, "--ready-file", ready.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        do {
            let deadline = Date().addingTimeInterval(5)
            while port == 0 {
                if let text = try? String(contentsOf: ready, encoding: .utf8), let value = Int(text) { port = value }
                guard Date() < deadline, process.isRunning else { throw BitbotError.invalid("Mock robot startup failed") }
                try await Task.sleep(for: .milliseconds(20))
            }
        } catch { stop(); throw error }
    }

    func stop() {
        if process.isRunning { process.terminate(); process.waitUntilExit() }
        try? FileManager.default.removeItem(at: ready)
    }
}
