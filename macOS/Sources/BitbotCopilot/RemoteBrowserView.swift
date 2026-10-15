// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import SwiftUI
import BitbotCore

struct RemoteBrowserView: View {
    let profile: RobotProfile
    let onDownload: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var directory: String
    @State private var entries: [RemoteEntry] = []
    @State private var selected: String?
    @State private var loading = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?

    init(profile: RobotProfile, onDownload: @escaping (URL) -> Void) {
        self.profile = profile; self.onDownload = onDownload
        _directory = State(initialValue: profile.dataDirectory)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("从机器人加载 CSV").font(.title2.bold())
                Spacer()
                Button("取消") { task?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("\(profile.sshUser)@\(profile.sshHost):\(String(profile.sshPort))").foregroundStyle(.secondary)
            HStack {
                Button { directory = (directory as NSString).deletingLastPathComponent; refresh() } label: { Image(systemName: "arrow.up") }
                TextField("远端目录", text: $directory).onSubmit { refresh() }
                Button("刷新") { refresh() }
            }.disabled(loading)
            if loading { ProgressView("正在传输…") }
            List(entries, selection: $selected) { entry in
                Label(entry.name, systemImage: entry.directory ? "folder" : "doc.text")
                    .tag(entry.name)
                    .onTapGesture(count: 2) {
                        if entry.directory { directory = join(entry.name); refresh() }
                        else { download(entry.name) }
                    }
            }.disabled(loading)
            if let error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Text("通过系统 SFTP 和 SSH 密钥连接。只显示目录和 CSV。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("打开") {
                    if let entry = entries.first(where: { $0.name == selected }) {
                        if entry.directory { directory = join(entry.name); refresh() }
                        else { download(entry.name) }
                    }
                }.disabled(selected == nil || loading).buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 720, height: 580)
        .onAppear { refresh() }
        .onDisappear { task?.cancel() }
    }
    private func join(_ name: String) -> String { (directory as NSString).appendingPathComponent(name) }
    private func refresh() {
        task?.cancel(); loading = true; error = nil; selected = nil
        let path = directory
        task = Task {
            do {
                let result = try await RemoteFiles.list(profile, directory: path)
                guard !Task.isCancelled else { return }
                entries = result
            } catch is CancellationError { return } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
    private func download(_ name: String) {
        guard !loading else { return }
        loading = true; error = nil
        let remote = join(name)
        task = Task {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bitbot-" + UUID().uuidString, isDirectory: true)
            let local = folder.appendingPathComponent(name)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try await RemoteFiles.download(profile, remotePath: remote, destination: local)
                try Task.checkCancellation()
                onDownload(local); dismiss()
            } catch {
                try? FileManager.default.removeItem(at: folder)
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
            loading = false
        }
    }
}
