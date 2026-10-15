// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import XCTest
@testable import BitbotCore

final class ProtocolTests: XCTestCase {
    func testCommandPreservesNestedJSONAndInt64BitPattern() throws {
        let data = try BitbotProtocol.command(["float": .floating(1.25), "press": .integer(1)])
        struct Event: Decodable { let name: String; let value: Int64 }
        struct Payload: Decodable { let events: [Event] }
        struct Envelope: Decodable { let type: String; let data: String }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        XCTAssertEqual(envelope.type, "events")
        let payload = try JSONDecoder().decode(Payload.self, from: Data(envelope.data.utf8))
        XCTAssertEqual(payload.events.first { $0.name == "float" }?.value, Int64(bitPattern: 1.25.bitPattern))
        XCTAssertEqual(payload.events.first { $0.name == "press" }?.value, 1)
    }
    func testMonitorEnvelopeAndAlignment() throws {
        let data = Data(#"{"type":"monitor_data","data":"{\"data\":[1,2.5,3]}"}"#.utf8)
        XCTAssertEqual(try BitbotProtocol.monitorData(data, count: 3), [1, 2.5, 3])
        XCTAssertThrowsError(try BitbotProtocol.monitorData(data, count: 2))
        XCTAssertNil(try BitbotProtocol.monitorData(Data(#"{"type":"ack","data":""}"#.utf8), count: 3))
        XCTAssertThrowsError(try BitbotProtocol.command([:]))
    }
    func testHeaderOrderingPreservesWireOrder() throws {
        let headers = try JSONDecoder().decode(DataHeaders.self, from: Data(#"{"kernel":["state"],"bus":{"devices":[{"name":"m1","type":"motor","headers":["position","velocity"]}]},"extra":["temp"]}"#.utf8))
        XCTAssertEqual(headers.channels, ["Kernel / state", "m1 / position", "m1 / velocity", "Extra / temp"])
    }
    func testCSVQuotingBOMAndCRLF() throws {
        let csv = try CSVData(text: "\u{FEFF}\"time\",\"sensor, \"\"A\"\"\"\r\n0,1.5\r\n1,2.5\r\n")
        XCTAssertEqual(csv.headers, ["time", "sensor, \"A\""])
        XCTAssertEqual(csv.rows, [[0, 1.5], [1, 2.5]])
        let embedded = try CSVData(text: "\"multi\nline\",b\n1,2")
        XCTAssertEqual(embedded.headers.first, "multi\nline")
    }
    func testCSVWithoutHeaderAndMalformedRows() throws {
        XCTAssertEqual(try CSVData(text: "0,1\n2,3").headers, ["Column 1", "Column 2"])
        for bad in ["", "a,b\n1", "a,b\n,\n1,2", "a,b\n1,nan", "a,b\n1,inf", "a,b\n1,word", "a,b\n\"1,2", "a,b\n\"1\"x,2"] {
            XCTAssertThrowsError(try CSVData(text: bad), bad)
        }
    }
    func testLiveCSVExportCanBeReadBack() throws {
        let text = CSVData.encode(headers: ["a,b", "c"], samples: [Sample(id: 1, time: 0.5, values: [1, 2])])
        let csv = try CSVData(text: text)
        XCTAssertEqual(csv.headers, ["elapsed_seconds", "a,b", "c"])
        XCTAssertEqual(csv.rows, [[0.5, 1, 2]])
    }
    func testLegacyProfileAndAutoRunImport() throws {
        let ini = """
        [FRONTEND]
        IP=192.168.1.5
        PORT=12888
        [BACKEND]
        PROTOCAL=ssh
        IP=192.168.1.5
        PORT=2222
        USERNAME=robot
        PASSWD=do-not-import
        PATH=/home/robot
        EXEC=start.sh
        [AUTORUNCOMMAND]
        size=1
        1\\KEY_NAME=" "
        1\\WAIT_UNTIL=kernel_idle
        1\\DURATION=500
        """
        let profile = try RobotProfile.importINI(ini, name: "机器人")
        XCTAssertEqual(profile.host, "192.168.1.5")
        XCTAssertEqual(profile.sshPort, 2222)
        XCTAssertTrue(profile.remote)
        XCTAssertEqual(profile.autoRun.first?.key, " ")
        XCTAssertEqual(profile.autoRun.first?.durationMS, 500)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(profile), as: UTF8.self).contains("do-not-import"))
    }
    @MainActor func testProfilePersistenceSwitchAndDelete() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProfileStore(directory: dir)
        let original = try XCTUnwrap(store.selected)
        var profile = RobotProfile(); profile.name = "测试机器人"; profile.port = 12999
        try store.save(profile)
        XCTAssertEqual(ProfileStore(directory: dir).selected?.id, profile.id)
        try store.select(original.id)
        try store.delete(profile.id)
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertThrowsError(try store.delete(original.id))
        profile.port = 0
        XCTAssertThrowsError(try store.save(profile))
        XCTAssertEqual(ProfileStore(directory: dir).profiles.count, 1)
    }
    func testShellAndSFTPPathsAreQuoted() throws {
        XCTAssertEqual(ShellArgument.quote("a'b;$(x)"), "'a'\\''b;$(x)'")
        XCTAssertEqual(try ShellArgument.sftpQuote("/a b/\"x\".csv"), "\"/a b/\\\"x\\\".csv\"")
        XCTAssertThrowsError(try ShellArgument.sftpQuote("a\nget /secret"))
        var profile = RobotProfile(); profile.remote = true; profile.sshHost = "-oProxyCommand=x"
        XCTAssertThrowsError(try profile.validate())
    }
}
