// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import SwiftUI
import BitbotCore

struct KeyFeedbackView: View {
    let connection: RobotConnection
    @Bindable var input: InputController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("按键反馈", systemImage: "keyboard").font(.title3.bold())
                Text(input.enabled ? "键盘 / 手柄就绪" : "输入已暂停")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(input.enabled ? Color.green.opacity(0.15) : Color.secondary.opacity(0.12), in: Capsule())
                    .foregroundStyle(input.enabled ? .green : .secondary)
                Spacer()
                Button("结束文本编辑") { input.focusControls() }
            }
            HStack(spacing: 16) {
                let latest = connection.latestControl
                Text(latest.map { keyLabel($0.key) } ?? "—")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .frame(minWidth: 72, minHeight: 58).padding(.horizontal, 12)
                    .background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 5) {
                    Text(latest?.event ?? "等待按键输入").font(.headline).lineLimit(1)
                    if let latest {
                        Text("\(latest.phase.rawValue) · 已发送 \(latest.value)")
                            .font(.callout).foregroundStyle(latest.phase == .pressed ? .green : .secondary)
                        Text(latest.date, format: .dateTime.hour().minute().second()).font(.caption.monospaced()).foregroundStyle(.secondary)
                    } else {
                        Text("键盘、手柄和点击下方按钮的反馈会显示在这里。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 10)], spacing: 10) {
                    ForEach(connection.controls) { control in
                        keyCard(control)
                    }
                }.padding(2)
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .top) { Rectangle().fill(Color.accentColor.opacity(0.5)).frame(height: 2) }
    }

    private func keyCard(_ control: ControlEvent) -> some View {
        let feedback = connection.controlFeedback[control.event]
        let pressed = feedback?.phase == .pressed
        return Button {
            Task { await connection.click(control.event) }
        } label: {
            HStack(spacing: 10) {
                Text(keyLabel(control.kb_key))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .frame(minWidth: 42, minHeight: 40)
                    .padding(.horizontal, 4)
                    .background(pressed ? Color.accentColor : Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                    .foregroundStyle(pressed ? .white : .primary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(control.event).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(feedback.map { $0.phase == .value ? $0.value : $0.phase.rawValue } ?? "未触发")
                        .font(.caption).foregroundStyle(pressed ? Color.accentColor : .secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(pressed ? Color.accentColor.opacity(0.12) : Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(pressed ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: pressed ? 2 : 1))
        }.buttonStyle(.plain)
        .help("\(control.event) · \(keyLabel(control.kb_key))")
        .accessibilityLabel("\(keyLabel(control.kb_key))，\(control.event)，\(feedback?.phase.rawValue ?? "未触发")")
    }

    private func keyLabel(_ key: String) -> String {
        if key == " " { return "Space" }
        return key.replacingOccurrences(of: "GAMEPAD_BUTTON_", with: "")
            .replacingOccurrences(of: "GAMEPAD_JOYSTICK_", with: "")
            .replacingOccurrences(of: "GAMEPAD_HAT_", with: "D-")
            .uppercased()
    }
}
