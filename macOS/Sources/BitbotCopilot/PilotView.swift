// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import SwiftUI
import BitbotCore

struct PilotView: View {
    enum Sheet: String, Identifiable { case input, backend; var id: String { rawValue } }
    @Environment(RobotConnection.self) private var connection
    @Environment(ProfileStore.self) private var profiles
    @State private var host = "127.0.0.1"
    @State private var port = 12888
    @State private var selected: Set<Int> = []
    @State private var search = ""
    @State private var display: DataDisplay = .table
    enum DataDisplay: String, CaseIterable { case table = "表格", curves = "曲线" }
    @State private var input = InputController()
    @State private var sheet: Sheet?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("机器人 IP / 主机", text: $host).frame(maxWidth: 240)
                TextField("端口", value: $port, format: .number.grouping(.never)).frame(width: 80)
                Button(connection.status == .disconnected ? "连接" : "断开") {
                    if connection.status == .disconnected { connection.connect(host: host, port: port) }
                    else { connection.disconnect() }
                }.buttonStyle(.borderedProminent)
                Spacer()
                Button("输入设备") { sheet = .input }.disabled(!connection.isConnected)
                Button("后端管理") { sheet = .backend }
                Text(connection.currentState).font(.headline)
            }.textFieldStyle(.roundedBorder).padding(20)
            Divider()
            if connection.isConnected {
                HStack {
                    Text("实时数据").font(.headline)
                    Picker("显示方式", selection: $display) {
                        ForEach(DataDisplay.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).frame(width: 160)
                    Spacer()
                    Button("导出实时 CSV") { exportSamples() }.disabled(connection.samples.isEmpty)
                }.padding(.horizontal, 20).padding(.vertical, 12)
                VSplitView {
                    Group {
                        switch display {
                        case .table:
                            TelemetryTablesView(tables: connection.headers?.tables ?? [], values: connection.values)
                        case .curves:
                            curveView
                        }
                    }.frame(minHeight: 180, maxHeight: .infinity)
                    KeyFeedbackView(connection: connection, input: input)
                        .frame(minHeight: 220, idealHeight: 280, maxHeight: 440)
                }
            } else {
                ContentUnavailableView(connection.status == .connecting ? "正在连接机器人" : "连接机器人开始监测", systemImage: "network", description: Text("连接已运行的 Bitbot HTTP/WebSocket 服务，默认端口为 12888。"))
            }
        }
        .onAppear {
            loadProfile(); input.start(connection)
        }
        .onDisappear { input.stop() }
        .onChange(of: connection.status) { _, _ in
            input.refreshAvailability(focus: true)
            display = .table
        }
        .sheet(item: $sheet, onDismiss: {
            if input.enabled { input.focusControls() }
        }) { item in
            switch item {
            case .input: InputView(input: input)
            case .backend: BackendView()
            }
        }
        .onChange(of: profiles.selectedID) { _, _ in loadProfile() }
        .onChange(of: connection.headers?.channels) { _, channels in selected = Set((channels ?? []).indices.prefix(3)) }
    }
    private var curveView: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                TextField("筛选通道", text: $search)
                List {
                    ForEach(Array((connection.headers?.channels ?? []).enumerated()), id: \.offset) { index, name in
                        if search.isEmpty || name.localizedCaseInsensitiveContains(search) {
                            Toggle(name, isOn: Binding(
                                get: { selected.contains(index) },
                                set: { if $0 { selected.insert(index) } else { selected.remove(index) } }
                            )).toggleStyle(.checkbox).font(.caption)
                        }
                    }
                }.listStyle(.plain)
            }.padding(16).frame(minWidth: 200, idealWidth: 250, maxWidth: 320)
            PlotView(headers: connection.headers?.channels ?? [], samples: connection.samples, selected: $selected)
        }
    }

    private func loadProfile() {
        if let profile = profiles.selected { host = profile.host; port = profile.port }
    }
    private func exportSamples() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "bitbot-live.csv"; panel.allowedContentTypes = [.commaSeparatedText]
        if panel.runModal() == .OK, let url = panel.url {
            do { try CSVData.encode(headers: connection.headers?.channels ?? [], samples: connection.samples).write(to: url, atomically: true, encoding: .utf8) }
            catch { connection.error = error.localizedDescription }
        }
    }
}
