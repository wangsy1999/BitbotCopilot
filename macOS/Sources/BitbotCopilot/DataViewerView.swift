// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import SwiftUI
import UniformTypeIdentifiers
import BitbotCore

struct DataViewerView: View {
    @Environment(ProfileStore.self) private var profiles
    @State private var remoteProfile: RobotProfile?
    @Environment(DataViewerModel.self) private var model
    @State private var search = ""

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack {
                Button("打开 CSV…", systemImage: "folder") { open() }
                    .keyboardShortcut("o").disabled(model.loading)
                Button("从机器人加载…", systemImage: "arrow.down.doc") { remoteProfile = profiles.selected }
                    .disabled(model.loading || profiles.selected?.remote != true)
                Text(model.filename).font(.headline).lineLimit(1)
                Spacer()
                if model.loading { ProgressView().controlSize(.small) }
                if let csv = model.csv { Text("\(String(csv.rows.count)) 条记录 · \(String(csv.headers.count)) 列").foregroundStyle(.secondary) }
            }.padding(20)
            Divider()
            if let csv = model.csv {
                HSplitView {
                    VStack(alignment: .leading) {
                        TextField("筛选通道", text: $search)
                        Picker("横轴", selection: $model.xColumn) {
                            Text("采样序号").tag(-1)
                            ForEach(csv.headers.indices, id: \.self) { Text(csv.headers[$0]).tag($0) }
                        }
                        List(csv.headers.indices.filter { search.isEmpty || csv.headers[$0].localizedCaseInsensitiveContains(search) }, id: \.self) { index in
                            Toggle(csv.headers[index], isOn: Binding(get: { model.selected.contains(index) }, set: { if $0 { model.selected.insert(index) } else { model.selected.remove(index) } })).toggleStyle(.checkbox)
                        }.listStyle(.plain)
                        Button("清除选择") { model.selected = [] }
                    }.padding(16).frame(minWidth: 220, idealWidth: 260, maxWidth: 340)
                    PlotView(headers: csv.headers, samples: model.samples, selected: $model.selected, xColumn: model.xColumn >= 0 ? model.xColumn : nil, allowsBoxZoom: true)
                        .id("\(model.datasetID)-\(model.xColumn)")
                }
            } else {
                ContentUnavailableView("查看实验数据", systemImage: "chart.xyaxis.line", description: Text("打开或拖入 CSV 文件，选择通道并比较曲线。"))
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in model.load(url) } }
            }
            return true
        }
        .sheet(item: $remoteProfile) { profile in
            RemoteBrowserView(profile: profile) { url in model.load(url, temporary: true) }
        }
        .alert("无法读取数据", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("好") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    private func open() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.commaSeparatedText]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { model.load(url) }
    }
}

@MainActor @Observable
final class DataViewerModel {
    var csv: CSVData?
    var samples: [Sample] = []
    var selected: Set<Int> = []
    var xColumn = -1
    var filename = ""
    var datasetID = UUID()
    var loading = false
    var error: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    func load(_ url: URL, temporary: Bool = false) {
        task?.cancel(); let token = UUID(); generation = token; loading = true
        task = Task {
            defer { if temporary { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) } }
            do {
                let (parsed, points) = try await Task.detached(priority: .userInitiated) {
                    let parsed = try CSVData(text: String(contentsOf: url, encoding: .utf8))
                    let points = parsed.rows.enumerated().map { Sample(id: $0.offset, time: Double($0.offset), values: $0.element) }
                    return (parsed, points)
                }.value
                guard !Task.isCancelled, generation == token else { return }
                csv = parsed; samples = points; datasetID = UUID()
                selected = Set(parsed.headers.indices.prefix(3)); xColumn = -1
                filename = url.lastPathComponent
            } catch { if generation == token { self.error = error.localizedDescription } }
            if generation == token { loading = false }
        }
    }
}
