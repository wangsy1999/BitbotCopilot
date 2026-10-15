// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import Foundation
import Observation

@MainActor @Observable
public final class RobotConnection {
    public enum Status: String { case disconnected = "未连接", connecting = "连接中", connected = "已连接" }
    public private(set) var status: Status = .disconnected
    public private(set) var states: [RobotState] = []
    public private(set) var controls: [ControlEvent] = []
    public private(set) var headers: DataHeaders?
    public private(set) var values: [Double] = []
    public private(set) var samples: [Sample] = []
    public private(set) var lastUpdate: Date?
    public private(set) var controlFeedback: [String: ControlFeedback] = [:]
    public private(set) var latestControl: ControlFeedback?
    public var error: String?
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var session: URLSession?
    @ObservationIgnored private var receiveTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var sampleID = 0
    @ObservationIgnored private var started = Date()

    public init() {}
    public var isConnected: Bool { status == .connected }
    public var sessionID: UUID { generation }
    public var currentState: String {
        guard isConnected, let value = values.first else { return "—" }
        return states.first { Double($0.id) == value }?.name ?? "未知状态 \(value)"
    }

    public func connect(host: String, port: Int) {
        disconnect()
        error = nil
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, (1...65535).contains(port), !host.contains("/"), !host.contains("@") else {
            error = "请输入有效的主机名和端口（1–65535）。"; return
        }
        var components = URLComponents()
        components.scheme = "http"; components.host = host; components.port = port
        guard let base = components.url else { error = "无效的连接地址。"; return }
        let token = generation
        status = .connecting
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: configuration)
        self.session = session
        deadlineTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            self?.fail(BitbotError.invalid("连接超时，请检查机器人地址和服务端口。"), token: token)
        }
        connectTask = Task { [weak self] in
            do {
                struct StateList: Decodable { let states: [RobotState] }
                async let stateData = Self.get(base.appendingPathComponent("monitor/stateslist"), session: session)
                async let controlData = Self.get(base.appendingPathComponent("setting/control/get"), session: session)
                async let headerData = Self.get(base.appendingPathComponent("monitor/headers"), session: session)
                let (s, c, h) = try await (stateData, controlData, headerData)
                let states = try JSONDecoder().decode(StateList.self, from: s).states
                let controls = try JSONDecoder().decode([ControlEvent].self, from: c)
                let headers = try JSONDecoder().decode(DataHeaders.self, from: h)
                guard !headers.channels.isEmpty else { throw BitbotError.invalid("机器人返回了空数据头。") }
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.states = states; self.controls = controls; self.headers = headers
                var ws = components; ws.scheme = "ws"; ws.path = "/console"
                guard let url = ws.url else { throw BitbotError.invalid("无效的 WebSocket 地址。") }
                let socket = session.webSocketTask(with: url)
                self.socket = socket; socket.resume()
                // A successful ping proves the WebSocket upgrade completed before enabling controls.
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    socket.sendPing { error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume() }
                    }
                }
                guard self.generation == token, !Task.isCancelled else { return }
                self.deadlineTask?.cancel(); self.deadlineTask = nil
                self.status = .connected; self.started = Date()
                self.receiveTask = Task { [weak self] in await self?.receive(socket, token: token) }
                self.pollTask = Task { [weak self] in
                    do {
                        while !Task.isCancelled {
                            try await socket.send(.string(BitbotProtocol.dataRequest))
                            try await Task.sleep(for: .milliseconds(100))
                            guard let self, self.generation == token else { return }
                            if Date().timeIntervalSince(self.lastUpdate ?? self.started) > 5 {
                                throw BitbotError.invalid("超过 5 秒未收到机器人数据，连接已关闭。")
                            }
                        }
                    } catch {
                        self?.fail(error, token: token)
                    }
                }
            } catch { self?.fail(error, token: token) }
        }
    }

    public func disconnect() {
        generation = UUID()
        connectTask?.cancel(); receiveTask?.cancel(); pollTask?.cancel(); deadlineTask?.cancel()
        deadlineTask = nil
        connectTask = nil; receiveTask = nil; pollTask = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        session?.invalidateAndCancel(); session = nil
        status = .disconnected; states = []; controls = []; headers = nil
        values = []; samples = []; lastUpdate = nil; sampleID = 0
        controlFeedback = [:]; latestControl = nil
    }

    public func send(_ events: [String: CommandValue]) async throws {
        guard isConnected, let socket else { throw BitbotError.invalid("请先连接机器人。") }
        let allowed = Set(controls.map(\.event))
        guard events.keys.allSatisfy({ allowed.contains($0) }) else { throw BitbotError.invalid("机器人未注册此控制事件。") }
        let token = generation
        do {
            try await socket.send(.data(BitbotProtocol.command(events)))
            guard generation == token else { return }
            let now = Date()
            for control in controls {
                guard let value = events[control.event] else { continue }
                let feedback = ControlFeedback(control: control, value: value, date: now)
                controlFeedback[control.event] = feedback; latestControl = feedback
            }
        }
        catch { fail(error, token: token); throw error }
    }

    public func click(_ event: String) async {
        let token = generation
        do { try await pulse(event) }
        catch is CancellationError {} catch { if generation == token { self.error = error.localizedDescription } }
    }

    public func pulse(_ event: String) async throws {
        let token = generation
        try Task.checkCancellation()
        try await send([event: .integer(1)])
        // Cancellation must not leave an event pressed on the robot.
        try? await Task.sleep(for: .milliseconds(110))
        guard generation == token else { throw CancellationError() }
        try await Task { @MainActor in
            guard self.generation == token else { return }
            try await self.send([event: .integer(2)])
        }.value
        try Task.checkCancellation()
    }

    private func receive(_ socket: URLSessionWebSocketTask, token: UUID) async {
        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                guard generation == token else { return }
                let data: Data
                switch message {
                case .data(let value): data = value
                case .string(let value): data = Data(value.utf8)
                @unknown default: continue
                }
                guard let values = try BitbotProtocol.monitorData(data, count: headers?.channels.count ?? 0) else { continue }
                self.values = values; lastUpdate = Date(); sampleID += 1
                samples.append(Sample(id: sampleID, time: Date().timeIntervalSince(started), values: values))
                if samples.count > 1200 { samples.removeFirst(samples.count - 1200) }
            }
        } catch { fail(error, token: token) }
    }

    private func fail(_ error: Error, token: UUID) {
        guard token == generation, !(error is CancellationError) else { return }
        disconnect(); self.error = error.localizedDescription
    }

    private static func get(_ url: URL, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("BITBOT COPILOT", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            throw BitbotError.invalid("HTTP 请求失败：\(url.path)")
        }
        return data
    }
}
