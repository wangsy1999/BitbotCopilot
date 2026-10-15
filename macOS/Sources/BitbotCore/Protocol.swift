// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import Foundation

public enum BitbotError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

public struct RobotState: Codable, Identifiable, Sendable {
    public let id: Int
    public let name: String
}

public struct ControlEvent: Codable, Identifiable, Sendable {
    public let event: String
    public let kb_key: String
    public var id: String { event }
}

public struct DataHeaders: Codable, Sendable {
    public struct Device: Codable, Sendable {
        public let name: String
        public let type: String
        public let headers: [String]
    }
    public struct Bus: Codable, Sendable { public let devices: [Device] }
    public let kernel: [String]
    public let bus: Bus
    public let extra: [String]
    public var channels: [String] {
        kernel.map { "Kernel / \($0)" }
        + bus.devices.flatMap { device in device.headers.map { "\(device.name) / \($0)" } }
        + extra.map { "Extra / \($0)" }
    }
}

public enum CommandValue: Sendable {
    case integer(Int64)
    case floating(Double)
    var wireValue: Int64 {
        switch self {
        case .integer(let value): return value
        case .floating(let value): return Int64(bitPattern: value.bitPattern)
        }
    }
}

public enum BitbotProtocol {
    public static let dataRequest = "{\"type\":\"request_data\",\"data\":\"\"}"

    public static func command(_ events: [String: CommandValue]) throws -> Data {
        struct Event: Encodable { let name: String; let value: Int64 }
        struct Payload: Encodable { let events: [Event] }
        struct Envelope: Encodable { let type: String; let data: String }
        guard !events.isEmpty else { throw BitbotError.invalid("控制事件不能为空。") }
        let encoder = JSONEncoder()
        let payload = try encoder.encode(Payload(events: events.sorted { $0.key < $1.key }.map {
            Event(name: $0.key, value: $0.value.wireValue)
        }))
        return try encoder.encode(Envelope(type: "events", data: String(decoding: payload, as: UTF8.self)))
    }

    public static func monitorData(_ data: Data, count: Int) throws -> [Double]? {
        struct Envelope: Decodable { let type: String; let data: String }
        struct Payload: Decodable { let data: [Double] }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.type == "monitor_data" else { return nil }
        let values = try JSONDecoder().decode(Payload.self, from: Data(envelope.data.utf8)).data
        guard values.count == count, values.allSatisfy(\.isFinite) else {
            throw BitbotError.invalid("实时数据与数据头不匹配，或包含无效数值。")
        }
        return values
    }
}

public struct Sample: Identifiable, Sendable {
    public let id: Int
    public let time: Double
    public let values: [Double]
    public init(id: Int, time: Double, values: [Double]) {
        self.id = id; self.time = time; self.values = values
    }
}
