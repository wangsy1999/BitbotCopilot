// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import SwiftUI
import UniformTypeIdentifiers
import BitbotCore

struct ProfilesView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(RobotConnection.self) private var connection
    @State private var editor: RobotProfile?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("机器人配置").font(.largeTitle.bold())
                Spacer()
                Button("导入旧版配置…") { importProfile() }
                Button("添加机器人", systemImage: "plus") { editor = RobotProfile() }
                    .buttonStyle(.borderedProminent)
            }
            Text("配置保存在本机 Application Support 中。切换机器人无需重启应用。")
                .foregroundStyle(.secondary)
            List {
                ForEach(store.profiles) { profile in
                    HStack(spacing: 16) {
                        Image(systemName: "cpu").font(.title).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(profile.name).font(.headline)
                            Text("\(profile.host):\(String(profile.port)) · \(profile.remote ? "SSH" : "本地后端")").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if profile.id == store.selectedID { Label("当前机器人", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                        else {
                            Button("使用") {
                                do { try store.select(profile.id); connection.disconnect() }
                                catch { self.error = error.localizedDescription }
                            }
                        }
                        Button("编辑") { editor = profile }
                        Button(role: .destructive) {
                            do {
                                let current = profile.id == store.selectedID
                                try store.delete(profile.id)
                                if current { connection.disconnect() }
                            } catch { self.error = error.localizedDescription }
                        } label: { Image(systemName: "trash") }.disabled(store.profiles.count <= 1)
                    }.padding(.vertical, 12)
                }
            }.listStyle(.inset)
        }.padding(28)
        .sheet(item: $editor) { profile in ProfileEditor(profile: profile) }
        .alert("配置提示", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func importProfile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "ini") ?? .plainText]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let profile = try RobotProfile.importINI(String(contentsOf: url, encoding: .utf8), name: url.deletingPathExtension().lastPathComponent)
                editor = profile
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct ProfileEditor: View {
    @Environment(ProfileStore.self) private var store
    @Environment(RobotConnection.self) private var connection
    @Environment(\.dismiss) private var dismiss
    @State var profile: RobotProfile
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("机器人配置").font(.title2.bold()); Spacer() }.padding(24)
            Form {
                Section("基本信息") { TextField("名称", text: $profile.name) }
                Section("前端连接 · HTTP / WebSocket") {
                    TextField("主机", text: $profile.host)
                    TextField("端口", value: $profile.port, format: .number.grouping(.never))
                }
                Section("后端启动") {
                    Toggle("通过 SSH 连接远端", isOn: $profile.remote)
                    if profile.remote {
                        TextField("SSH 主机", text: $profile.sshHost)
                        TextField("SSH 端口", value: $profile.sshPort, format: .number.grouping(.never))
                        TextField("用户名", text: $profile.sshUser)
                        Text("使用系统 OpenSSH 密钥或 ssh-agent。请先在终端成功连接此主机并确认主机指纹；旧 Profile 的密码不会被导入。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("工作目录", text: $profile.executableDirectory)
                    TextField("可执行文件 / 脚本名称", text: $profile.executable)
                    TextField("数据目录", text: $profile.dataDirectory)
                }
                Section("自动初始化") {
                    ForEach($profile.autoRun) { $step in
                        HStack {
                            TextField("按键，如 w / 空格", text: $step.key)
                            TextField("等待状态（可留空）", text: $step.waitUntil)
                            TextField("毫秒", value: $step.durationMS, format: .number.grouping(.never)).frame(width: 85)
                            Button(role: .destructive) { profile.autoRun.removeAll { $0.id == step.id } } label: { Image(systemName: "minus.circle") }
                        }
                    }
                    Button("添加动作", systemImage: "plus") { profile.autoRun.append(AutoRunStep()) }
                    Text("每步发送按下和释放事件，随后等待指定状态或等待时长结束。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            if let error { Text(error).foregroundStyle(.red).font(.callout).padding(.horizontal, 24) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存并使用") {
                    do {
                        try store.save(profile); connection.disconnect(); dismiss()
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.padding(20)
        }.frame(width: 680, height: 720)
    }
}
