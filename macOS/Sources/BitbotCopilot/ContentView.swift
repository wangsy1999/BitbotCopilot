// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import SwiftUI
import BitbotCore

enum Page: String, CaseIterable, Identifiable {
    case home = "概览", pilot = "控制台", data = "数据查看", profiles = "机器人配置", about = "关于与致谢"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .pilot: return "gamecontroller"
        case .data: return "waveform.path.ecg"
        case .profiles: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }
}

struct ContentView: View {
    @Environment(RobotConnection.self) private var connection
    @Environment(ProfileStore.self) private var profiles
    @State private var page: Page? = .home

    init(initialPage: Page = .home) {
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        @Bindable var connection = connection
        @Bindable var profiles = profiles
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 20) {
                Label("BITBOT", systemImage: "cpu")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .padding(.horizontal, 16).padding(.top, 24)
                List(Page.allCases, selection: $page) { item in
                    Label(item.rawValue, systemImage: item.icon).tag(item)
                        .padding(.vertical, 5)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("当前机器人").font(.caption).foregroundStyle(.secondary)
                    Text(profiles.selected?.name ?? "未选择配置").font(.headline)
                    Label(connection.status.rawValue, systemImage: "circle.fill")
                        .font(.caption).foregroundStyle(connection.isConnected ? .green : .secondary)
                    Text("Copilot · macOS 原生版").font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(16)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            Group {
                switch page ?? .home {
                case .home: HomeView { page = $0 }
                case .pilot: PilotView()
                case .data: DataViewerView()
                case .profiles: ProfilesView()
                case .about: AboutView()
                }
            }
            .navigationTitle((page ?? .home).rawValue)
            .toolbar {
                ToolbarItem {
                    Label(connection.status.rawValue, systemImage: connection.isConnected ? "network" : "network.slash")
                        .foregroundStyle(connection.isConnected ? .green : .secondary)
                }
            }
        }
        .alert("连接提示", isPresented: Binding(get: { connection.error != nil }, set: { if !$0 { connection.error = nil } })) {
            Button("好") { connection.error = nil }
        } message: { Text(connection.error ?? "") }
        .alert("配置提示", isPresented: Binding(get: { profiles.error != nil }, set: { if !$0 { profiles.error = nil } })) {
            Button("好") { profiles.error = nil }
        } message: { Text(profiles.error ?? "") }
    }
}

struct HomeView: View {
    @Environment(RobotConnection.self) private var connection
    @Environment(ProfileStore.self) private var profiles
    let navigate: (Page) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Bitbot Copilot").font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("连接机器人，观察每一次变化。") .font(.title3).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "cpu").font(.system(size: 52, weight: .light)).foregroundStyle(.tint)
                }
                .padding(.vertical, 14)
                GroupBox {
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(profiles.selected?.name ?? "请选择机器人").font(.title2.bold())
                            Text(verbatim: profiles.selected.map { "\($0.host):\(String($0.port))" } ?? "在机器人配置中添加连接信息")
                                .foregroundStyle(.secondary).monospaced()
                        }
                        Spacer()
                        Button(connection.isConnected ? "打开控制台" : "连接已有任务") {
                            if !connection.isConnected, let p = profiles.selected { connection.connect(host: p.host, port: p.port) }
                            navigate(.pilot)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(profiles.selected == nil || connection.status == .connecting)
                    }.padding(14)
                }
                HStack(alignment: .top, spacing: 16) {
                    feature("控制与监测", detail: "实时状态、设备数据、键盘与手柄控制", icon: "gamecontroller", page: .pilot)
                    feature("查看实验数据", detail: "打开本地 CSV，选择并比较数据曲线", icon: "chart.xyaxis.line", page: .data)
                    feature("管理机器人", detail: "保存连接、启动配置，导入原有 Profile", icon: "slider.horizontal.3", page: .profiles)
                }
                GroupBox("当前状态") {
                    HStack {
                        metric("连接", connection.status.rawValue)
                        Divider()
                        metric("机器人状态", connection.currentState)
                        Divider()
                        metric("数据通道", String(connection.headers?.channels.count ?? 0))
                        Divider()
                        metric("已缓存采样", String(connection.samples.count))
                    }.padding(16).frame(height: 80)
                }
                Text("先在机器人端启动程序，再连接已有任务。需要由 Copilot 启动时，可在控制台使用后端管理。")
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(32)
        }
    }
    private func feature(_ title: String, detail: String, icon: String, page: Page) -> some View {
        Button { navigate(page) } label: {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: icon).font(.title).foregroundStyle(.tint)
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).frame(height: 42, alignment: .top)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview { ContentView().environment(RobotConnection()).environment(ProfileStore()).environment(BackendManager()).environment(AutoRunner()).environment(DataViewerModel()) }
