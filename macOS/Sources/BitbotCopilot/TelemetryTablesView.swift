// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import SwiftUI
import BitbotCore

struct TelemetryTablesView: View {
    let tables: [TelemetryTable]
    let values: [Double]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(tables) { table in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(table.title, systemImage: table.id == "kernel" ? "cpu" : table.id == "extra" ? "list.bullet.rectangle" : "gearshape.2")
                                .font(.headline)
                            Spacer()
                            Text("\(String(table.rows.count)) 行 · \(String(table.columns.count)) 列").font(.caption).foregroundStyle(.secondary)
                        }
                        ScrollView(.horizontal) {
                            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                                GridRow {
                                    cell("设备 / 字段", header: true, first: true)
                                    ForEach(table.columns.indices, id: \.self) { column in
                                        cell(table.columns[column], header: true)
                                    }
                                }.background(Color(nsColor: .controlBackgroundColor))
                                ForEach(Array(table.rows.enumerated()), id: \.element.id) { index, row in
                                    GridRow {
                                        cell(row.name, first: true)
                                        ForEach(row.channels, id: \.self) { channel in
                                            cell(values.indices.contains(channel)
                                                ? values[channel].formatted(.number.grouping(.never).precision(.significantDigits(8))) : "—")
                                        }
                                    }.background(index.isMultiple(of: 2) ? Color(nsColor: .textBackgroundColor) : Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                }
                            }
                            .textSelection(.enabled)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }.padding(20)
        }
    }
    private func cell(_ text: String, header: Bool = false, first: Bool = false) -> some View {
        Text(text)
            .font(header || first ? .system(.callout, weight: .semibold) : .system(.body, design: .monospaced))
            .foregroundStyle(header ? .secondary : .primary)
            .lineLimit(1)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(minWidth: first ? 150 : 120, maxWidth: .infinity, alignment: first || header ? .leading : .trailing)
            .overlay(alignment: .bottom) { Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.4)).frame(height: 0.5) }
    }
}
