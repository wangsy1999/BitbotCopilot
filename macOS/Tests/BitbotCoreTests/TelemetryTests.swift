// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import XCTest
@testable import BitbotCore

final class TelemetryTests: XCTestCase {
    func testDeviceGroupsKeepOriginalWireOffsets() throws {
        let headers = try JSONDecoder().decode(DataHeaders.self, from: Data(#"{"kernel":["state","cycle"],"bus":{"devices":[{"name":"left","type":"motor","headers":["position","velocity"]},{"name":"imu","type":"imu","headers":["yaw"]},{"name":"right","type":"motor","headers":["position","velocity"]}]},"extra":["temperature"]}"#.utf8))
        let tables = headers.tables
        XCTAssertEqual(tables.map(\.title), ["内核状态", "motor", "imu", "用户数据"])
        let motors = try XCTUnwrap(tables.first { $0.title == "motor" })
        XCTAssertEqual(motors.columns, ["position", "velocity"])
        XCTAssertEqual(motors.rows.map(\.name), ["left", "right"])
        XCTAssertEqual(motors.rows.map(\.channels), [[2, 3], [5, 6]])
        XCTAssertEqual(tables.last?.rows.first?.channels, [7])
        let values: [Double] = [1, 20, 0.1, 0.2, 30, 0.3, 0.4, 25]
        XCTAssertEqual(motors.rows[1].channels.map { values[$0] }, [0.3, 0.4])
    }

    func testDifferentSchemasDoNotMislabelDeviceValues() throws {
        let headers = try JSONDecoder().decode(DataHeaders.self, from: Data(#"{"kernel":[],"bus":{"devices":[{"name":"a","type":"motor","headers":["position"]},{"name":"empty","type":"motor","headers":[]},{"name":"b","type":"motor","headers":["velocity","position"]}]},"extra":[]}"#.utf8))
        XCTAssertEqual(headers.tables.count, 2)
        XCTAssertEqual(headers.tables.map(\.columns), [["position"], ["velocity", "position"]])
        XCTAssertEqual(headers.tables[1].rows[0].channels, [1, 2])
    }

    func testAnalogValueOneIsNotDisplayedAsButtonPress() {
        let control = ControlEvent(event: "axis", kb_key: "GAMEPAD_JOYSTICK_LX")
        let feedback = ControlFeedback(control: control, value: .integer(1), date: Date())
        XCTAssertEqual(feedback.phase, .value)
    }
}
