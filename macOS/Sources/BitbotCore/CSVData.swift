// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import Foundation

public struct CSVData: Sendable {
    public let headers: [String]
    public let rows: [[Double]]

    public init(text: String) throws {
        let records = try Self.records(text)
        guard let first = records.first, !first.isEmpty else { throw BitbotError.invalid("CSV 文件为空。") }
        let hasHeader = !first.allSatisfy { Double($0.trimmingCharacters(in: .whitespaces)) != nil }
        headers = hasHeader ? first : first.indices.map { "Column \($0 + 1)" }
        guard headers.allSatisfy({ !$0.isEmpty }) else { throw BitbotError.invalid("CSV 列名不能为空。") }
        let dataRecords = hasHeader ? Array(records.dropFirst()) : records
        var parsed: [[Double]] = []; parsed.reserveCapacity(dataRecords.count)
        for (index, fields) in dataRecords.enumerated() {
            let line = index + (hasHeader ? 2 : 1)
            guard fields.count == headers.count else { throw BitbotError.invalid("CSV 第 \(line) 条记录列数不一致。") }
            let numbers = fields.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard numbers.count == fields.count, numbers.allSatisfy(\.isFinite) else {
                throw BitbotError.invalid("CSV 第 \(line) 条记录包含非数值或无效数值。")
            }
            parsed.append(numbers)
        }
        guard !parsed.isEmpty else { throw BitbotError.invalid("CSV 没有数值记录。") }
        rows = parsed
    }

    // RFC 4180 quoting, including doubled quotes, embedded newlines and UTF-8 BOM.
    private static func records(_ text: String) throws -> [[String]] {
        let chars = Array(text.replacingOccurrences(of: "\u{FEFF}", with: ""))
        var records: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, closed = false, index = 0
        func finishField() { row.append(field); field = ""; closed = false }
        func finishRow() {
            finishField()
            if row.count != 1 || !row[0].trimmingCharacters(in: .whitespaces).isEmpty { records.append(row) }
            row = []
        }
        while index < chars.count {
            let char = chars[index]
            if quoted {
                if char == "\"" {
                    if index + 1 < chars.count, chars[index + 1] == "\"" { field.append("\""); index += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(char) }
            } else if char == "," { finishField() }
            else if char == "\n" || char == "\r" || char == "\r\n" {
                finishRow()
                if char == "\r", index + 1 < chars.count, chars[index + 1] == "\n" { index += 1 }
            } else if char == "\"", field.isEmpty, !closed { quoted = true }
            else {
                guard !closed, char != "\"" else { throw BitbotError.invalid("CSV 引号格式无效。") }
                field.append(char)
            }
            index += 1
        }
        guard !quoted else { throw BitbotError.invalid("CSV 引号未闭合。") }
        if !field.isEmpty || !row.isEmpty || closed { finishRow() }
        return records
    }

    public static func encode(headers: [String], samples: [Sample]) -> String {
        func quoted(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        return ([(["elapsed_seconds"] + headers).map(quoted).joined(separator: ",")]
            + samples.map { ([String($0.time)] + $0.values.map { String($0) }).joined(separator: ",") })
            .joined(separator: "\n") + "\n"
    }
}
