// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import Foundation
import Observation

public enum ShellArgument {
    public static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    public static func sftpQuote(_ value: String) throws -> String {
        guard !value.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\0" }) else {
            throw BitbotError.invalid("文件路径不能包含换行符或空字符。")
        }
        return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "?", with: "\\?")
            .replacingOccurrences(of: "[", with: "\\[") + "\""
    }
}

@MainActor @Observable
public final class BackendManager {
    public private(set) var running = false
    public private(set) var output = ""
    public var error: String?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var pipe: Pipe?

    public init() {}
    public func start(_ profile: RobotProfile) {
        guard !running else { return }
        do {
            try profile.validate()
            guard !profile.executable.isEmpty, !profile.executable.contains("\0") else {
                throw BitbotError.invalid("请配置后端可执行文件。")
            }
            let process = Process(), pipe = Pipe()
            if profile.remote {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                process.arguments = Self.sshArguments(profile) + [
                    "cd " + ShellArgument.quote(profile.executableDirectory) + " && exec " + ShellArgument.quote("./" + profile.executable)
                ]
            } else {
                let directory = URL(fileURLWithPath: (profile.executableDirectory as NSString).expandingTildeInPath, isDirectory: true)
                process.currentDirectoryURL = directory
                process.executableURL = directory.appendingPathComponent(profile.executable)
            }
            process.standardOutput = pipe; process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            output = ""; error = nil
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let text = String(decoding: data, as: UTF8.self)
                Task { @MainActor in self?.append(text) }
            }
            process.terminationHandler = { [weak self, weak pipe] process in
                pipe?.fileHandleForReading.readabilityHandler = nil
                Task { @MainActor in
                    guard let self, self.process === process else { return }
                    self.running = false; self.process = nil; self.pipe = nil
                    self.append("\n进程结束，退出码 \(process.terminationStatus)。\n")
                }
            }
            try process.run()
            self.process = process; self.pipe = pipe; running = true
        } catch { self.error = error.localizedDescription }
    }
    public func stop() { if let process, process.isRunning { process.terminate() } }
    public func clearOutput() { output = "" }
    private func append(_ text: String) {
        output += text
        if output.count > 100_000 { output = String(output.suffix(80_000)) }
    }
    public static func sshArguments(_ profile: RobotProfile) -> [String] {
        ["-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-o", "ServerAliveInterval=5",
         "-o", "ServerAliveCountMax=2", "-p", String(profile.sshPort), "-l", profile.sshUser, profile.sshHost]
    }
}

public struct RemoteEntry: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let directory: Bool
}

public enum RemoteFiles {
    // OpenSSH batch mode preserves system known_hosts and ssh-agent behaviour.
    public static func list(_ profile: RobotProfile, directory: String) async throws -> [RemoteEntry] {
        try profile.validate()
        let command = "ls -1F " + (try ShellArgument.sftpQuote(directory)) + "\n"
        let text = try await runSFTP(profile, batch: command)
        return text.components(separatedBy: .newlines).compactMap { line in
            guard !line.isEmpty, !line.hasPrefix("sftp>"), !line.hasPrefix("Connected to ") else { return nil }
            let directory = line.hasSuffix("/")
            let clean = directory ? String(line.dropLast()) : line
            let name = (clean as NSString).lastPathComponent
            guard name != ".", name != "..", !name.isEmpty,
                  directory || name.lowercased().hasSuffix(".csv") else { return nil }
            return RemoteEntry(name: name, directory: directory)
        }.sorted { $0.directory == $1.directory ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.directory }
    }

    public static func download(_ profile: RobotProfile, remotePath: String, destination: URL) async throws {
        try profile.validate()
        _ = try await runSFTP(profile, batch: "get " + ShellArgument.sftpQuote(remotePath) + " " + ShellArgument.sftpQuote(destination.path) + "\n")
    }

    private static func runSFTP(_ profile: RobotProfile, batch: String) async throws -> String {
        let job = ProcessJob()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                job.start(profile: profile, batch: batch, continuation: continuation)
            }
        } onCancel: { job.cancel() }
    }
}

// Lock protects Process state shared by the termination and cancellation callbacks.
private final class ProcessJob: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    func start(profile: RobotProfile, batch: String, continuation: CheckedContinuation<String, Error>) {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { continuation.resume(throwing: CancellationError()); return }
        let process = Process(), input = Pipe()
        // A temporary file prevents a full stdout pipe from deadlocking large directory listings.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try Data().write(to: url)
            let output = try FileHandle(forWritingTo: url)
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sftp")
            process.arguments = ["-q", "-b", "-", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8",
                                 "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=2",
                                 "-P", String(profile.sshPort), profile.sshUser + "@" + profile.sshHost]
            process.standardInput = input; process.standardOutput = output; process.standardError = output
            process.terminationHandler = { [self] process in
                try? output.close()
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                try? FileManager.default.removeItem(at: url)
                lock.lock(); let wasCancelled = cancelled; self.process = nil; lock.unlock()
                if wasCancelled { continuation.resume(throwing: CancellationError()) }
                else if process.terminationStatus == 0 { continuation.resume(returning: text) }
                else { continuation.resume(throwing: BitbotError.invalid("SFTP 失败：\(text)")) }
            }
            try process.run(); self.process = process
            input.fileHandleForWriting.write(Data(batch.utf8)); try? input.fileHandleForWriting.close()
        } catch {
            try? FileManager.default.removeItem(at: url)
            continuation.resume(throwing: error)
        }
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let process, process.isRunning { process.terminate() }
    }
}
