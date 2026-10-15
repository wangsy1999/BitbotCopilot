// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import SwiftUI
import BitbotCore

@MainActor @Observable
final class AutoRunner {
    var progress: String?
    var error: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    func start(profile: RobotProfile, connection: RobotConnection) {
        guard task == nil else { return }
        let token = connection.sessionID
        task = Task {
            defer { progress = nil; task = nil }
            do {
                guard connection.isConnected else { throw BitbotError.invalid("自动初始化前请先连接机器人。") }
                let mapping = Dictionary(profile.autoRun.map { step in
                    (step.id, connection.controls.first { $0.kb_key == step.key || $0.event == step.key }?.event)
                }, uniquingKeysWith: { first, _ in first })
                guard profile.autoRun.allSatisfy({ mapping[$0.id] ?? nil != nil }) else {
                    throw BitbotError.invalid("自动初始化包含机器人未注册的按键，请检查配置。")
                }
                for (index, step) in profile.autoRun.enumerated() {
                    try Task.checkCancellation()
                    guard connection.sessionID == token, connection.isConnected,
                          let event = mapping[step.id] ?? nil else { throw BitbotError.invalid("机器人连接已改变，自动初始化已停止。") }
                    progress = "\(index + 1)/\(profile.autoRun.count) · \(event)"
                    // Always complete the release pair, including when cancellation arrives during the pulse.
                    try await connection.pulse(event)
                    let deadline = Date().addingTimeInterval(Double(step.durationMS) / 1000)
                    repeat {
                        try Task.checkCancellation()
                        guard connection.isConnected, connection.sessionID == token else { throw BitbotError.invalid("机器人已断开连接。") }
                        if !step.waitUntil.isEmpty, connection.currentState == step.waitUntil { break }
                        if Date() >= deadline { break }
                        try await Task.sleep(for: .milliseconds(100))
                    } while true
                }
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    func cancel() { task?.cancel() }
}

struct BackendView: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(RobotConnection.self) private var connection
    @Environment(BackendManager.self) private var backend
    @Environment(AutoRunner.self) private var runner
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var backend = backend
        @Bindable var runner = runner
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("后端管理").font(.title2.bold()); Spacer(); Button("完成") { dismiss() } }
            if let profile = profiles.selected {
                Text(profile.remote ? "SSH · \(profile.sshUser)@\(profile.sshHost):\(profile.sshPort)" : "本地进程")
                    .foregroundStyle(.secondary)
                Text("\(profile.executableDirectory)/\(profile.executable)").font(.callout.monospaced()).textSelection(.enabled)
                HStack {
                    Button("启动后端", systemImage: "play.fill") { backend.start(profile) }
                        .disabled(backend.running)
                    Button("停止进程", systemImage: "stop.fill") { backend.stop() }.disabled(!backend.running)
                    Spacer()
                    Button("连接前端") { connection.connect(host: profile.host, port: profile.port) }
                        .disabled(connection.status != .disconnected)
                }
                Text("启动后等待服务就绪，再连接前端。SSH 模式通过系统密钥认证；停止按钮结束本次 SSH 会话，远端程序是否随之退出取决于其实现。")
                    .font(.caption).foregroundStyle(.secondary)
                GroupBox("自动初始化") {
                    HStack {
                        Text(runner.progress ?? "已配置 \(profile.autoRun.count) 个动作")
                        Spacer()
                        if runner.progress != nil { Button("取消") { runner.cancel() } }
                        else {
                            Button("执行初始化") { runner.start(profile: profile, connection: connection) }
                                .disabled(!connection.isConnected || profile.autoRun.isEmpty)
                        }
                    }.padding(8)
                }
            }
            HStack { Text("进程输出").font(.headline); Spacer(); Button("清空") { backend.clearOutput() } }
            ScrollView {
                Text(backend.output.isEmpty ? "进程输出将在这里显示。" : backend.output)
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }.background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }.padding(24).frame(width: 760, height: 610)
        .alert("后端提示", isPresented: Binding(get: { backend.error != nil || runner.error != nil }, set: { if !$0 { backend.error = nil; runner.error = nil } })) {
            Button("好") { backend.error = nil; runner.error = nil }
        } message: { Text(backend.error ?? runner.error ?? "") }
    }
}

struct InputView: View {
    @Bindable var input: InputController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("输入设备").font(.title2.bold()); Spacer(); Button("完成") { dismiss() } }
            Label(input.controllerName, systemImage: "gamecontroller")
            Text("连接后可直接使用键盘和手柄，无需开启开关。输入仅在控制台可见且应用位于前台时发送；输入框内正常打字。摇杆沿用旧版横轴方向与 32768 缩放。")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 50) {
                VirtualStick(title: "左摇杆") { x, y in input.joystick(x: x, y: y, right: false) }
                VirtualStick(title: "右摇杆") { x, y in input.joystick(x: x, y: y, right: true) }
            }.frame(maxWidth: .infinity).disabled(!input.enabled)
            Text("当前按键：" + input.activeKeys.sorted().map { $0 == " " ? "Space" : $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(width: 640)
    }
}

private struct VirtualStick: View {
    let title: String
    let update: (Double, Double) -> Void
    @State private var offset = CGSize.zero
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(.quaternary)
                Path { p in p.move(to: CGPoint(x: 0, y: 85)); p.addLine(to: CGPoint(x: 170, y: 85)); p.move(to: CGPoint(x: 85, y: 0)); p.addLine(to: CGPoint(x: 85, y: 170)) }
                    .stroke(.secondary.opacity(0.25), style: StrokeStyle(dash: [4]))
                Circle().fill(.tint.opacity(0.7)).frame(width: 52, height: 52).offset(offset)
            }.frame(width: 170, height: 170)
                .contentShape(Circle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let dx = value.location.x - 85, dy = value.location.y - 85
                    let length = max(60, hypot(dx, dy))
                    offset = CGSize(width: dx / length * 60, height: dy / length * 60)
                    update(-dx / length, -dy / length)
                }.onEnded { _ in offset = .zero; update(0, 0) })
            Text(title).font(.headline)
        }.accessibilityLabel(title)
        .onDisappear { update(0, 0) }
    }
}
