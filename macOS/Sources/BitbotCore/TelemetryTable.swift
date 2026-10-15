// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import Foundation

public struct TelemetryTable: Identifiable, Sendable {
    public struct Row: Identifiable, Sendable {
        public let id: Int
        public let name: String
        public let channels: [Int]
    }
    public let id: String
    public let title: String
    public let columns: [String]
    public var rows: [Row]
}

extension DataHeaders {
    /// Keep wire offsets intact even when devices of the same type are interleaved.
    public var tables: [TelemetryTable] {
        var result: [TelemetryTable] = []
        var offset = kernel.count
        if !kernel.isEmpty {
            result.append(TelemetryTable(id: "kernel", title: "内核状态", columns: kernel,
                rows: [.init(id: 0, name: "Kernel", channels: Array(kernel.indices))]))
        }
        for (index, device) in bus.devices.enumerated() {
            let channels = Array(offset..<(offset + device.headers.count))
            offset += device.headers.count
            guard !device.headers.isEmpty else { continue }
            let row = TelemetryTable.Row(id: index, name: device.name, channels: channels)
            let title = device.type.isEmpty ? "设备" : device.type
            // A different schema gets its own table rather than mislabelling values.
            if let group = result.firstIndex(where: { $0.id.hasPrefix("device-") && $0.title == title && $0.columns == device.headers }) {
                result[group].rows.append(row)
            } else {
                result.append(TelemetryTable(id: "device-\(index)", title: title, columns: device.headers, rows: [row]))
            }
        }
        if !extra.isEmpty {
            result.append(TelemetryTable(id: "extra", title: "用户数据", columns: extra,
                rows: [.init(id: 0, name: "User Info", channels: Array(offset..<(offset + extra.count)))]))
        }
        return result
    }
}

public struct ControlFeedback: Identifiable, Sendable {
    public enum Phase: String, Sendable { case pressed = "按下", released = "已释放", value = "数值" }
    public var id: String { event }
    public let event: String
    public let key: String
    public let phase: Phase
    public let value: String
    public let date: Date

    init(control: ControlEvent, value: CommandValue, date: Date) {
        event = control.event; key = control.kb_key; self.date = date
        switch value {
        case .integer(let number):
            if control.kb_key.hasPrefix("GAMEPAD_JOYSTICK") { phase = .value }
            else { phase = number == 1 ? .pressed : number == 2 ? .released : .value }
            self.value = String(number)
        case .floating(let number):
            phase = .value; self.value = number.formatted(.number.grouping(.never).precision(.significantDigits(6)))
        }
    }
}
