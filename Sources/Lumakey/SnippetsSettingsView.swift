import AppKit
import LumakeyCore
import SwiftUI

@MainActor
final class SnippetsSettingsController: ObservableObject {
    @Published var snippets: [SnippetItem] = []
    @Published var filterQuery: String = ""
    @Published var editingID: UUID?
    @Published var draftTitle: String = ""
    @Published var draftKeyword: String = ";"
    @Published var draftCategory: String = "通用"
    @Published var draftContent: String = ""
    @Published var statusMessage: String?

    private let store: SnippetStore

    init(store: SnippetStore = .shared) {
        self.store = store
        reload()
    }

    var filteredSnippets: [SnippetItem] {
        let q = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return snippets }
        return snippets.filter {
            $0.keyword.localizedCaseInsensitiveContains(q)
                || $0.title.localizedCaseInsensitiveContains(q)
                || $0.category.localizedCaseInsensitiveContains(q)
                || $0.content.localizedCaseInsensitiveContains(q)
        }
    }

    var livePreviewText: String {
        let clip = NSPasteboard.general.string(forType: .string) ?? "(当前剪贴板文本)"
        return SnippetStore.expand(draftContent, clipboardText: clip)
    }

    func reload() {
        snippets = store.allSnippets()
        if let id = editingID, let found = snippets.first(where: { $0.id == id }) {
            select(found)
        } else if let first = snippets.first {
            select(first)
        } else {
            startNew()
        }
    }

    func select(_ item: SnippetItem) {
        editingID = item.id; draftTitle = item.title; draftKeyword = item.keyword
        draftCategory = item.category; draftContent = item.content
    }

    func startNew() {
        editingID = nil; draftTitle = "新快捷短语"; draftKeyword = ";new"
        draftCategory = "通用"; draftContent = "记录时间：{{datetime}}"
    }

    func insertPlaceholder(_ token: String) { draftContent += token }

    func save(notify viewModel: AppViewModel?) {
        let item = SnippetItem(id: editingID ?? UUID(), title: draftTitle, keyword: draftKeyword, content: draftContent, category: draftCategory)
        do {
            let saved = try store.upsert(item)
            editingID = saved.id; snippets = store.allSnippets()
            let msg = "已保存短语：\(saved.title) (\(saved.keyword))"
            statusMessage = msg; viewModel?.serviceMessage = msg
        } catch { statusMessage = error.localizedDescription }
    }

    func delete(_ item: SnippetItem, notify viewModel: AppViewModel?) {
        do {
            try store.delete(id: item.id)
            if editingID == item.id { editingID = nil }
            reload()
            let msg = "已删除短语：\(item.title)"
            statusMessage = msg
            viewModel?.serviceMessage = msg
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func resetDefaults(notify viewModel: AppViewModel?) {
        if let restored = try? store.resetToDefaults() {
            snippets = restored
            if let first = restored.first { select(first) }
            let msg = "已恢复默认示例短语词库"
            statusMessage = msg
            viewModel?.serviceMessage = msg
        }
    }

    func copyExpanded(_ item: SnippetItem, notify viewModel: AppViewModel?) {
        let clip = NSPasteboard.general.string(forType: .string)
        let expanded = SnippetStore.expand(item.content, clipboardText: clip)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(expanded, forType: .string)
        let msg = "已展开并复制：\(item.title)"
        statusMessage = msg
        viewModel?.serviceMessage = msg
    }
}

struct SnippetsSettingsView: View {
    var viewModel: AppViewModel?
    @StateObject private var ctrl = SnippetsSettingsController()

    init(viewModel: AppViewModel? = nil) {
        self.viewModel = viewModel
    }

    private let placeholders = ["{{date}}", "{{datetime}}", "{{uuid}}", "{{clipboard}}"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeroHeader(
                symbol: "text.quote",
                topColor: .cyan,
                bottomColor: .indigo,
                title: "快捷短语词库 (Snippets)",
                subtitle: "输入触发前缀（如 ;date / ;sh）毫秒展开常用语、脚本模板与动态剪贴板占位符。"
            ) {
                HStack(spacing: 8) {
                    Button("新建短语") { ctrl.startNew() }
                        .buttonStyle(GlassPillButtonStyle(prominent: true))
                    Button("恢复示例") { ctrl.resetDefaults(notify: viewModel) }
                        .buttonStyle(GlassPillButtonStyle())
                }
            }

            HStack(spacing: 12) {
                snippetListPane
                editorPane
                    .frame(width: 380)
            }
        }
    }

    private var snippetListPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassInputField(symbol: "magnifyingglass", placeholder: "搜索短语标题、触发词或内容…", text: $ctrl.filterQuery)
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(ctrl.filteredSnippets) { item in
                        let selected = ctrl.editingID == item.id
                        HStack(spacing: 10) {
                            Text(item.keyword.isEmpty ? "—" : item.keyword)
                                .font(.caption.monospaced().weight(.bold))
                                .foregroundStyle(.cyan)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(LiquidColors.pillSurface, in: Capsule())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.callout.weight(.semibold)).lineLimit(1)
                                Text(item.content.replacingOccurrences(of: "\n", with: " ↵ "))
                                    .font(.caption2).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Button("复制") { ctrl.copyExpanded(item, notify: viewModel) }
                                .buttonStyle(GlassPillButtonStyle())
                            Button("删除") { ctrl.delete(item, notify: viewModel) }
                                .buttonStyle(GlassPillButtonStyle())
                        }
                        .padding(9)
                        .background(selected ? LiquidColors.highlightGlow : LiquidColors.pillSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: LiquidRadii.row, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: LiquidRadii.row, style: .continuous)
                                .strokeBorder(selected ? Color.cyan.opacity(0.45) : LiquidColors.pillBorder, lineWidth: 0.75)
                        }
                        .onTapGesture { ctrl.select(item) }
                    }
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
        }
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(ctrl.editingID == nil ? "创建新短语" : "编辑快捷短语").font(.callout.weight(.bold))
                Spacer()
                if let msg = ctrl.statusMessage {
                    Text(msg).font(.caption2).foregroundStyle(.cyan).lineLimit(1)
                }
            }
            HStack(spacing: 8) {
                GlassInputField(symbol: "bolt.fill", placeholder: "触发词 (;sig)", text: $ctrl.draftKeyword)
                GlassInputField(symbol: "folder", placeholder: "分类", text: $ctrl.draftCategory)
            }
            GlassInputField(symbol: "tag", placeholder: "短语显示名称", text: $ctrl.draftTitle)

            HStack(spacing: 5) {
                Text("插入变量:").font(.caption2).foregroundStyle(LiquidColors.textSecondary)
                ForEach(placeholders, id: \.self) { token in
                    Button(token) { ctrl.insertPlaceholder(token) }
                        .buttonStyle(GlassPillButtonStyle())
                }
            }

            TextEditor(text: $ctrl.draftContent)
                .font(.system(.caption, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 96, maxHeight: 130)
                .background(LiquidColors.inputFieldSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
                        .strokeBorder(LiquidColors.inputFieldBorder, lineWidth: 0.9)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("实时展开预览").font(.caption2.weight(.semibold)).foregroundStyle(LiquidColors.textSecondary)
                Text(ctrl.livePreviewText.isEmpty ? "(空内容)" : ctrl.livePreviewText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(LiquidColors.textPrimary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))

            Button("保存快捷短语") { ctrl.save(notify: viewModel) }
                .buttonStyle(GlassPillButtonStyle(prominent: true))
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }
}
