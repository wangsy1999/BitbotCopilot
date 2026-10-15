// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import SwiftUI

enum AppAttribution {
    static let copyright = "Copyright © 2026 Siyuan Wang"
    static func text(_ name: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Legal"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "无法读取 \(name)。请查看项目源码中的 LICENSE、COPYRIGHT 和 ACKNOWLEDGEMENTS.md。"
        }
        return text
    }
}

struct AboutView: View {
    @State private var document: LicenseDocument?
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 20) {
                    if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
                        Image(nsImage: icon).resizable().frame(width: 88, height: 88).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bitbot Copilot").font(.largeTitle.bold())
                        Text("macOS 原生版 · \(version)").foregroundStyle(.secondary)
                        Text(AppAttribution.copyright).font(.callout).textSelection(.enabled)
                    }
                }
                GroupBox("项目与许可证") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("版权：Siyuan Wang")
                        Text("本项目以 GNU General Public License version 3 发布。程序不提供任何担保；完整条款见许可证。")
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("软件许可证") { document = .init(title: "GNU GPL v3", file: "LICENSE") }
                            Button("版权声明") { document = .init(title: "版权声明", file: "COPYRIGHT") }
                            Link("项目源码", destination: URL(string: "https://github.com/ZzzzzzS/BitbotCopilot")!)
                            Link("Bitbot", destination: URL(string: "https://bitbot.lmy.name/")!)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }
                GroupBox("致谢") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("感谢原版 Bitbot Copilot 作者")
                            .font(.callout).foregroundStyle(.secondary)
                        Text("zishun zhou").font(.title2.bold()).textSelection(.enabled)
                        Text("本 macOS 原生版本基于原版项目迁移与开发。")
                            .foregroundStyle(.secondary)
                        Button("完整致谢") { document = .init(title: "致谢", file: "ACKNOWLEDGEMENTS.md") }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }
            }.padding(28)
        }
        .sheet(item: $document) { document in LicenseTextView(document: document) }
        .frame(minWidth: 620, minHeight: 500)
    }
}

private struct LicenseDocument: Identifiable {
    let title: String
    let file: String
    var id: String { file }
}

private struct LicenseTextView: View {
    let document: LicenseDocument
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(document.title).font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                Text(AppAttribution.text(document.file))
                    .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }.background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }.padding(24).frame(width: 740, height: 640)
    }
}

struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("关于 Bitbot Copilot") { openWindow(id: "about") }
        }
    }
}

#Preview { AboutView() }
