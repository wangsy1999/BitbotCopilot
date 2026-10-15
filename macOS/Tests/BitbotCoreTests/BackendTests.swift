// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import XCTest
@testable import BitbotCore

final class BackendTests: XCTestCase {
    @MainActor func testLocalProcessOutputAndTermination() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("test.sh")
        try "#!/bin/sh\necho backend-output\necho backend-error >&2\nexit 7\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        var profile = RobotProfile(); profile.executableDirectory = dir.path; profile.executable = "test.sh"
        let backend = BackendManager()
        backend.start(profile)
        XCTAssertNil(backend.error)
        let deadline = Date().addingTimeInterval(3)
        while backend.running, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(backend.running)
        XCTAssertTrue(backend.output.contains("backend-output"))
        XCTAssertTrue(backend.output.contains("backend-error"))
        XCTAssertTrue(backend.output.contains("退出码 7"))
    }
    @MainActor func testInvalidExecutableIsReported() {
        var profile = RobotProfile(); profile.executable = "does-not-exist-bitbot-test"
        let backend = BackendManager(); backend.start(profile)
        XCTAssertFalse(backend.running)
        XCTAssertNotNil(backend.error)
    }
}
