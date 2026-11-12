// Command palette structure and row geometry adapted from beUI (MIT).
// Glass material follows ExpoKit's native material-blur approach. See THIRD_PARTY.md.
import AppKit
import SwiftUI

final class SearchModel: ObservableObject {
    let isDemo = Bundle.main.url(forResource: "demo-tabs", withExtension: "json") != nil
    @Published var query = ""
    @Published var tabs: [BrowserTab] = []
    @Published var selected = 0
    @Published var loading = false
    @Published var activating = false
    @Published var message: String?
    let bridge = BrowserBridge()
    var dismiss: (() -> Void)?
    private var bindings: [SpaceBinding] = {
        guard let data = UserDefaults.standard.data(forKey: "spaceBindings") else { return [] }
        return (try? JSONDecoder().decode([SpaceBinding].self, from: data)) ?? []
    }()

    var results: [BrowserTab] {
        let terms = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return tabs.filter { tab in
            let text = [tab.title, tab.url, tab.profileName, tab.spaceName].joined(separator: " ")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return terms.allSatisfy { text.contains($0) }
        }
    }

    func refresh() {
        guard !loading && !activating else { return }
        if isDemo, let url = Bundle.main.url(forResource: "demo-tabs", withExtension: "json") {
            do { tabs = try JSONDecoder().decode([BrowserTab].self, from: Data(contentsOf: url)) }
            catch { message = "无法读取演示数据。" }
            return
        }
        loading = true
        message = nil
        bridge.send(BridgeRequest(action: "list", bindings: bindings)) { result in
            self.loading = false
            switch result {
            case .success(let response) where response.ok:
                let selectedID = self.results[safe: self.selected]?.id
                self.tabs = response.tabs ?? []
                self.selected = self.results.firstIndex { $0.id == selectedID } ?? min(self.selected, max(0, self.results.count - 1))
            case .success(let response): self.message = response.error
            case .failure(let error): self.message = error.localizedDescription
            }
        }
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selected = (selected + delta + results.count) % results.count
        if NSWorkspace.shared.isVoiceOverEnabled, let tab = results[safe: selected] {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
                .announcement: "\(tab.title)，\(tab.profileName)，\(tab.spaceName)",
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ])
        }
    }

    func activate(_ tab: BrowserTab? = nil) {
        if isDemo { dismiss?(); return }
        guard !activating else { return }
        guard let target = tab ?? results[safe: selected] else { return }
        activating = true
        bridge.send(BridgeRequest(action: "activate", targetId: target.id, windowId: target.windowId, contextId: target.contextId)) { result in
            self.activating = false
            switch result {
            case .success(let response) where response.ok: self.dismiss?()
            case .success(let response): self.message = response.error
            case .failure(let error): self.message = error.localizedDescription
            }
        }
    }

    func bind(_ tab: BrowserTab, to space: SpaceChoice) {
        bindings.removeAll { $0.windowId == tab.windowId || ($0.contextId == tab.contextId && $0.spaceId == space.id) }
        bindings.append(SpaceBinding(windowId: tab.windowId, contextId: tab.contextId, spaceId: space.id))
        if let data = try? JSONEncoder().encode(bindings) { UserDefaults.standard.set(data, forKey: "spaceBindings") }
        refresh()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

private struct GlassSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct SearchView: View {
    @ObservedObject var model: SearchModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索标签页标题或网址", text: $model.query)
                    .font(.system(size: 16)).textFieldStyle(.plain).focused($focused)
                    .onChange(of: model.query) { _ in model.selected = 0 }
                    .onSubmit { model.activate() }
                    .accessibilityLabel("搜索所有 profile 和空间中的标签页")
                if model.loading || model.activating { ProgressView().controlSize(.small) }
                Button("esc") { model.dismiss?() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                    .accessibilityLabel("关闭搜索")
            }
            .padding(.horizontal, 20).frame(height: 64)
            Divider().opacity(0.5)

            if let message = model.message {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.circle").font(.title2)
                    Text(message).font(.system(size: 13)).multilineTextAlignment(.center)
                    Button("重新连接") { model.refresh() }
                }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.results.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "rectangle.on.rectangle").font(.title2).foregroundStyle(.secondary)
                    Text(model.loading ? "正在读取标签页…" : "没有匹配的标签页")
                        .font(.system(size: 14))
                    if !model.loading { Text("试试其他标题、网址、profile 或空间名").font(.system(size: 12)).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(model.results.enumerated()), id: \.element.id) { index, tab in
                                row(tab, index: index).id(tab.id)
                            }
                        }.padding(8)
                    }
                    .onChange(of: model.selected) { index in
                        if model.results.indices.contains(index) { proxy.scrollTo(model.results[index].id, anchor: nil) }
                    }
                }
            }
            Divider().opacity(0.5)
            HStack(spacing: 14) {
                Text("\(model.isDemo ? "演示数据 · " : "")\(model.results.count) 个标签页").monospacedDigit()
                Spacer()
                Text("↑↓ 选择   ↩ 切换")
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).keyboardShortcut("r", modifiers: .command)
                    .help("刷新标签页 · ⌘R").accessibilityLabel("刷新标签页")
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.horizontal, 20).frame(height: 38)
        }
        .background(GlassSurface())
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onReceive(NotificationCenter.default.publisher(for: .paletteFocus)) { _ in focused = true }
        .onAppear { focused = true }
    }

    private func row(_ tab: BrowserTab, index: Int) -> some View {
        HStack(spacing: 12) {
            Button { model.activate(tab) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "globe").font(.system(size: 17)).foregroundStyle(.secondary).frame(width: 22)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(tab.title).font(.system(size: 14)).lineLimit(1)
                        Text(tab.displayURL).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if tab.spaceId != nil || tab.candidates.isEmpty {
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(tab.profileName).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                            Text(tab.spaceName).font(.system(size: 12)).lineLimit(1)
                                .help("空间 ID \(tab.spaceId.map(String.init) ?? "待确认")")
                        }.frame(maxWidth: 180, alignment: .trailing)
                    }
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("切换到 \(tab.title)，\(tab.displayURL)，\(tab.profileName)，\(tab.spaceName)")
            .accessibilityAddTraits(index == model.selected ? .isSelected : [])
            if tab.spaceId == nil && !tab.candidates.isEmpty {
                VStack(alignment: .trailing, spacing: 5) {
                    Button(tab.profileName) { model.activate(tab) }
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).buttonStyle(.plain)
                    Menu {
                        Text("同名页面存在歧义，请选择实际所属空间")
                        ForEach(tab.candidates) { space in
                            Button("\(space.name) · #\(space.id)") { model.bind(tab, to: space) }
                        }
                    } label: { Text(tab.spaceName).font(.system(size: 12)) }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help("选定后会记住这个浏览器窗口与空间的关联")
                }.frame(maxWidth: 180, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .background(index == model.selected ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovering in if hovering { model.selected = index } }
    }
}

extension Notification.Name {
    static let paletteFocus = Notification.Name("EgoTabSearch.paletteFocus")
}
