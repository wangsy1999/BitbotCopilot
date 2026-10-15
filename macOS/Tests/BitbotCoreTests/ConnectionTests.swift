// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import XCTest
@testable import BitbotCore

final class ConnectionTests: XCTestCase {
    @MainActor func testHTTPWebSocketMonitorAndBinaryCommands() async throws {
        let server = try await MockRobot()
        defer { server.stop() }
        let connection = RobotConnection()
        defer { connection.disconnect() }
        connection.connect(host: "127.0.0.1", port: server.port)
        try await eventually { connection.values.count == 4 }
        XCTAssertEqual(connection.currentState, "kernel_idle")
        XCTAssertEqual(connection.values, [1, 12, 1.5, 30])
        XCTAssertEqual(connection.headers?.channels.last, "Extra / temp")
        XCTAssertFalse(connection.samples.isEmpty)
        await connection.click("walk")
        XCTAssertEqual(connection.controlFeedback["walk"]?.phase, .released)
        XCTAssertEqual(connection.controlFeedback["walk"]?.key, "w")
        try await connection.send(["axis": .integer(-16384)])
        XCTAssertEqual(connection.latestControl?.value, "-16384")
        XCTAssertEqual(connection.latestControl?.phase, .value)
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(server.port)/testing/events")!)
        struct Event: Decodable { let name: String; let value: Int64 }
        let events = try JSONDecoder().decode([Event].self, from: data)
        XCTAssertEqual(events.filter { $0.name == "walk" }.map(\.value), [1, 2])
        XCTAssertEqual(events.last?.value, -16384)
        do { try await connection.send(["unregistered": .integer(1)]); XCTFail("Unknown event accepted") }
        catch { XCTAssertTrue(connection.isConnected) }
        connection.disconnect()
        XCTAssertTrue(connection.values.isEmpty)
        XCTAssertTrue(connection.samples.isEmpty)
        XCTAssertTrue(connection.controlFeedback.isEmpty)
        XCTAssertNil(connection.latestControl)
        XCTAssertEqual(connection.status, .disconnected)
    }

    @MainActor func testMalformedDataClosesConnection() async throws {
        let server = try await MockRobot(mode: "mismatch")
        defer { server.stop() }
        let connection = RobotConnection()
        defer { connection.disconnect() }
        connection.connect(host: "127.0.0.1", port: server.port)
        try await eventually { connection.error != nil }
        XCTAssertEqual(connection.status, .disconnected)
        XCTAssertTrue(connection.values.isEmpty)
    }

    @MainActor func testCancelledPulseStillReleasesControl() async throws {
        let server = try await MockRobot()
        defer { server.stop() }
        let connection = RobotConnection()
        defer { connection.disconnect() }
        connection.connect(host: "127.0.0.1", port: server.port)
        try await eventually { connection.isConnected }
        let pulse = Task { try await connection.pulse("walk") }
        try await Task.sleep(for: .milliseconds(50))
        pulse.cancel()
        do { try await pulse.value; XCTFail("Cancellation was not propagated") } catch is CancellationError {}
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(server.port)/testing/events")!)
        let events = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(events.compactMap { $0["value"] as? Int }, [1, 2])
    }

    @MainActor func testCancelledHandshakeCannotOverwriteNewSession() async throws {
        let stalled = try await MockRobot(mode: "stall")
        let healthy = try await MockRobot()
        defer { stalled.stop(); healthy.stop() }
        let connection = RobotConnection()
        defer { connection.disconnect() }
        connection.connect(host: "127.0.0.1", port: stalled.port)
        try await Task.sleep(for: .milliseconds(200))
        connection.connect(host: "127.0.0.1", port: healthy.port)
        try await eventually { !connection.values.isEmpty }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(connection.isConnected)
        XCTAssertNil(connection.error)
    }

    @MainActor func testInvalidAddressAndConnectionRefusal() async throws {
        let connection = RobotConnection()
        connection.connect(host: "http://bad", port: 0)
        XCTAssertNotNil(connection.error)
        connection.connect(host: "127.0.0.1", port: 1)
        try await eventually { connection.error != nil }
        XCTAssertEqual(connection.status, .disconnected)
    }

    @MainActor private func eventually(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            guard Date() < deadline else { XCTFail("Timed out waiting for mock robot"); throw BitbotError.invalid("Test timeout") }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
}

private final class MockRobot {
    let process = Process()
    let ready = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var port = 0
    init(mode: String = "normal") async throws {
        let fixture = Bundle.module.url(forResource: "robot_server", withExtension: "py", subdirectory: "Fixtures")!
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [fixture.path, "--ready-file", ready.path, "--mode", mode]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        do {
            let deadline = Date().addingTimeInterval(5)
            while port == 0 {
                if let text = try? String(contentsOf: ready, encoding: .utf8), let value = Int(text) { port = value }
                if Date() > deadline { throw BitbotError.invalid("Mock server startup failed") }
                try await Task.sleep(for: .milliseconds(20))
            }
        } catch { stop(); throw error }
    }
    func stop() {
        if process.isRunning { process.terminate(); process.waitUntilExit() }
        try? FileManager.default.removeItem(at: ready)
    }
}
