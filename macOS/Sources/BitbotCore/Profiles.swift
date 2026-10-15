// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import Foundation
import Observation

public struct AutoRunStep: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var key = ""
    public var waitUntil = ""
    public var durationMS = 30000
    public init() {}
}

public struct RobotProfile: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name = "新机器人"
    public var host = "127.0.0.1"
    public var port = 12888
    public var remote = false
    public var sshHost = "127.0.0.1"
    public var sshPort = 22
    public var sshUser = "bitbot"
    public var executableDirectory = "/"
    public var executable = "main_app"
    public var dataDirectory = "/home"
    public var autoRun: [AutoRunStep] = []
    public init() {}

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw BitbotError.invalid("配置名称不能为空。") }
        guard !host.isEmpty, !host.contains("/"), !host.contains("@"), (1...65535).contains(port) else {
            throw BitbotError.invalid("请输入有效的机器人地址和端口。")
        }
        if remote {
            guard !sshHost.isEmpty, !sshHost.hasPrefix("-"), !sshHost.contains(where: \.isWhitespace),
                  !sshHost.contains("@"), !sshUser.isEmpty, !sshUser.hasPrefix("-"),
                  !sshUser.contains(where: \.isWhitespace), !sshUser.contains("@"), (1...65535).contains(sshPort) else {
                throw BitbotError.invalid("SSH 主机、用户名或端口无效。")
            }
        }
        guard autoRun.allSatisfy({ !$0.key.isEmpty && $0.durationMS >= 0 && $0.durationMS <= 3_600_000 }) else {
            throw BitbotError.invalid("自动初始化需要有效按键，等待时间应在 0–3600000 毫秒之间。")
        }
    }

    public static func importINI(_ text: String, name: String) throws -> RobotProfile {
        var entries: [String: String] = [:]
        var section = ""
        for raw in text.replacingOccurrences(of: "\u{FEFF}", with: "").components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") { section = String(line.dropFirst().dropLast()); continue }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
            value = value.replacingOccurrences(of: "\\\\", with: "\\")
            entries[section + "/" + key] = value
        }
        guard entries["FRONTEND/IP"] != nil || entries["BACKEND/PROTOCAL"] != nil else {
            throw BitbotError.invalid("不是有效的 Bitbot Profile INI 文件。")
        }
        var p = RobotProfile(); p.name = name
        p.host = entries["FRONTEND/IP"] ?? p.host
        p.port = Int(entries["FRONTEND/PORT"] ?? "12888") ?? 0
        p.remote = entries["BACKEND/PROTOCAL"] == "ssh"
        p.sshHost = entries["BACKEND/IP"] ?? p.host
        p.sshPort = Int(entries["BACKEND/PORT"] ?? "22") ?? 0
        p.sshUser = entries["BACKEND/USERNAME"] ?? p.sshUser
        p.executableDirectory = entries["BACKEND/PATH"] ?? p.executableDirectory
        p.executable = entries["BACKEND/EXEC"] ?? p.executable
        p.dataDirectory = entries["BACKEND/DATAPATH"] ?? p.dataDirectory
        let count = min(max(Int(entries["AUTORUNCOMMAND/size"] ?? "0") ?? 0, 0), 1000)
        if count > 0 {
            for index in 1...count {
                let prefix = "AUTORUNCOMMAND/\(index)\\"
                var step = AutoRunStep()
                step.key = entries[prefix + "KEY_NAME"] ?? ""
                step.waitUntil = entries[prefix + "WAIT_UNTIL"] ?? ""
                if step.waitUntil == "NAN" { step.waitUntil = "" }
                step.durationMS = Int(entries[prefix + "DURATION"] ?? "30000") ?? 30000
                p.autoRun.append(step)
            }
        }
        try p.validate()
        return p
    }
}

@MainActor @Observable
public final class ProfileStore {
    public private(set) var profiles: [RobotProfile] = []
    public private(set) var selectedID: UUID?
    public var error: String?
    @ObservationIgnored private let url: URL
    private struct Archive: Codable { let selectedID: UUID?; let profiles: [RobotProfile] }

    public init(directory: URL? = nil) {
        let directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BitbotCopilot", isDirectory: true)
        url = directory.appendingPathComponent("profiles.json")
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
                guard !archive.profiles.isEmpty, Set(archive.profiles.map(\.id)).count == archive.profiles.count else {
                    throw BitbotError.invalid("配置文件内容无效。")
                }
                profiles = archive.profiles
                selectedID = profiles.contains(where: { $0.id == archive.selectedID }) ? archive.selectedID : profiles.first?.id
            } else {
                var profile = RobotProfile(); profile.name = "本机仿真"
                profiles = [profile]; selectedID = profile.id
            }
        } catch { self.error = "读取配置失败：\(error.localizedDescription)" }
    }
    public var selected: RobotProfile? { profiles.first { $0.id == selectedID } }
    public func select(_ id: UUID) throws {
        guard profiles.contains(where: { $0.id == id }) else { return }
        try persist(profiles, selected: id); selectedID = id
    }
    public func save(_ profile: RobotProfile) throws {
        try profile.validate()
        var updated = profiles
        if let index = updated.firstIndex(where: { $0.id == profile.id }) { updated[index] = profile }
        else { updated.append(profile) }
        try persist(updated, selected: profile.id)
        profiles = updated; selectedID = profile.id
    }
    public func delete(_ id: UUID) throws {
        guard profiles.count > 1 else { throw BitbotError.invalid("至少保留一个机器人配置。") }
        let updated = profiles.filter { $0.id != id }
        let selected = selectedID == id ? updated.first?.id : selectedID
        try persist(updated, selected: selected)
        profiles = updated; selectedID = selected
    }
    private func persist(_ profiles: [RobotProfile], selected: UUID?) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Archive(selectedID: selected, profiles: profiles)).write(to: url, options: .atomic)
    }
}
