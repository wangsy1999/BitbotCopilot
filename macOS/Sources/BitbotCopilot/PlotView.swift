// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import SwiftUI
import Charts
import BitbotCore

struct PlotView: View {
    let headers: [String]
    let samples: [Sample]
    @Binding var selected: Set<Int>
    var xColumn: Int? = nil
    var allowsBoxZoom = false
    @State private var zoom = 1.0
    @State private var cursor: Double?
    @State private var mode: Interaction = .box
    @State private var viewport: PlotViewport?
    @State private var history: [PlotViewport] = []
    @State private var dragRect: CGRect?
    @State private var dragViewport: PlotViewport?
    private enum Interaction: String, CaseIterable { case box = "框选缩放", pan = "拖动浏览" }

    private var xBounds: ClosedRange<Double> {
        let xs = samples.map { xValue($0) }
        let lower = xs.min() ?? 0, upper = xs.max() ?? 1
        return lower...max(lower + 0.001, upper)
    }
    private var yBounds: ClosedRange<Double> {
        var lower = Double.infinity, upper = -Double.infinity
        for sample in samples {
            for column in shownIndices {
                lower = min(lower, sample.values[column]); upper = max(upper, sample.values[column])
            }
        }
        guard lower.isFinite, upper.isFinite else { return 0...1 }
        let padding = max((upper - lower) * 0.05, max(abs(lower), abs(upper)) * 0.001, 0.001)
        return (lower - padding)...(upper + padding)
    }
    private var fullViewport: PlotViewport { PlotViewport(x: xBounds, y: yBounds) }
    private var visible: PlotViewport { viewport ?? fullViewport }
    private var shownIndices: [Int] { selected.sorted().filter { headers.indices.contains($0) } }
    private func xValue(_ sample: Sample) -> Double {
        if let xColumn, sample.values.indices.contains(xColumn) { return sample.values[xColumn] }
        return sample.time
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(xColumn.map { headers[$0] } ?? (allowsBoxZoom ? "采样序号" : "时间（秒）"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if allowsBoxZoom {
                    Picker("图表操作", selection: $mode) {
                        ForEach(Interaction.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).frame(width: 200)
                    Button("上一步") {
                        if let previous = history.popLast() { viewport = previous; cursor = nil }
                    }.disabled(history.isEmpty)
                } else {
                    Text("缩放").font(.caption)
                    Slider(value: $zoom, in: 1...20).frame(width: 110).accessibilityLabel("曲线缩放")
                }
                Button("重置") { reset() }
            }
            if samples.isEmpty || shownIndices.isEmpty {
                ContentUnavailableView("暂无曲线", systemImage: "chart.xyaxis.line", description: Text("选择数据通道后在这里查看曲线。"))
            } else {
                if allowsBoxZoom {
                    chart
                        .chartXScale(domain: visible.x)
                        .chartYScale(domain: visible.y)
                        .chartOverlay { proxy in
                            GeometryReader { geometry in
                                if let anchor = proxy.plotFrame {
                                    interactionOverlay(in: geometry[anchor])
                                }
                            }
                        }
                    Text(mode == .box ? "在绘图区拖出矩形，同时放大横纵轴；单击查看数据。" : "拖动平移当前视图；单击查看数据。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    chart
                        .chartScrollableAxes(.horizontal)
                        .chartXScale(domain: xBounds)
                        .chartXVisibleDomain(length: (xBounds.upperBound - xBounds.lowerBound) / zoom)
                        .chartXSelection(value: $cursor)
                }
                if let cursor, let nearest = samples.min(by: { abs(xValue($0) - cursor) < abs(xValue($1) - cursor) }) {
                    Text("X: \(xValue(nearest).formatted(.number.grouping(.never).precision(.fractionLength(4))))  " + shownIndices.map {
                        "\(headers[$0]): \(nearest.values[$0].formatted(.number.grouping(.never).precision(.significantDigits(6))))"
                    }.joined(separator: "   "))
                    .font(.caption.monospaced()).textSelection(.enabled).lineLimit(2)
                }
            }
        }
        .padding(16)
        .onChange(of: selected) { _, _ in if allowsBoxZoom { reset() } }
        .onChange(of: mode) { _, _ in dragRect = nil; dragViewport = nil }
    }

    private var chart: some View {
        let plotSamples = samplesInViewport
        return Chart {
            ForEach(shownIndices, id: \.self) { column in
                // Bound rendering cost while preserving extrema in each bucket.
                ForEach(PlotSampling.reduce(plotSamples, column: column, limit: 1800)) { sample in
                    LineMark(x: .value("X", xValue(sample)), y: .value("数值", sample.values[column]), series: .value("通道", String(column)))
                        .foregroundStyle(by: .value("通道", "\(column + 1). \(headers[column])"))
                }
            }
            if let cursor { RuleMark(x: .value("光标", cursor)).foregroundStyle(.secondary).lineStyle(StrokeStyle(dash: [4])) }
        }
        .chartXAxis {
            AxisMarks(format: FloatingPointFormatStyle<Double>.number.grouping(.never).precision(.significantDigits(6)))
        }
        .chartYAxis {
            AxisMarks(format: FloatingPointFormatStyle<Double>.number.grouping(.never).precision(.significantDigits(6)))
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .chartPlotStyle { content in content.clipped() }
    }

    private var samplesInViewport: [Sample] {
        guard allowsBoxZoom, let viewport else { return samples }
        // Re-sample the visible region after zooming so detail is not lost to full-file decimation.
        return samples.indices.compactMap { index in
            let x = xValue(samples[index])
            func crosses(_ other: Int) -> Bool {
                guard samples.indices.contains(other) else { return false }
                let next = xValue(samples[other])
                return min(x, next) <= viewport.x.upperBound && max(x, next) >= viewport.x.lowerBound
            }
            return viewport.x.contains(x) || crosses(index - 1) || crosses(index + 1) ? samples[index] : nil
        }
    }

    private func interactionOverlay(in plot: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())
            if let dragRect {
                Rectangle().fill(Color.accentColor.opacity(0.15))
                    .overlay(Rectangle().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
                    .frame(width: dragRect.width, height: dragRect.height)
                    .offset(x: dragRect.minX, y: dragRect.minY)
                    .allowsHitTesting(false)
            }
        }
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { drag in
                guard plot.contains(drag.startLocation), plot.width > 0, plot.height > 0 else { return }
                if dragViewport == nil { dragViewport = visible }
                guard let original = dragViewport else { return }
                if mode == .box {
                    let end = original.clamped(drag.location, to: plot)
                    dragRect = CGRect(x: min(drag.startLocation.x, end.x), y: min(drag.startLocation.y, end.y),
                                      width: abs(end.x - drag.startLocation.x), height: abs(end.y - drag.startLocation.y))
                } else {
                    viewport = original.panning(from: drag.startLocation, to: drag.location, in: plot, within: fullViewport)
                }
            }
            .onEnded { drag in
                defer { dragRect = nil; dragViewport = nil }
                guard let original = dragViewport else { return }
                if mode == .box, let next = original.selecting(from: drag.startLocation, to: drag.location, in: plot) {
                    history.append(original)
                    if history.count > 50 { history.removeFirst() }
                    viewport = next; cursor = nil
                } else if hypot(drag.translation.width, drag.translation.height) < 6 {
                    let point = original.clamped(drag.location, to: plot)
                    cursor = original.x.lowerBound + Double((point.x - plot.minX) / plot.width) * (original.x.upperBound - original.x.lowerBound)
                }
            })
        .accessibilityLabel(mode == .box ? "拖动框选放大曲线" : "拖动平移曲线")
    }

    private func reset() {
        zoom = 1; cursor = nil; viewport = nil; history = []; dragRect = nil; dragViewport = nil
    }
}

enum PlotSampling {
    static func reduce(_ samples: [Sample], column: Int, limit: Int) -> [Sample] {
        guard samples.count > limit else { return samples }
        let size = max(1, Int(ceil(Double(samples.count) / Double(limit / 2))))
        var result: [Sample] = []
        for start in stride(from: 0, to: samples.count, by: size) {
            let bucket = samples[start..<min(start + size, samples.count)]
            guard let low = bucket.min(by: { $0.values[column] < $1.values[column] }),
                  let high = bucket.max(by: { $0.values[column] < $1.values[column] }) else { continue }
            if low.id == high.id { result.append(low) }
            else { result.append(contentsOf: low.id < high.id ? [low, high] : [high, low]) }
        }
        return result
    }
}
