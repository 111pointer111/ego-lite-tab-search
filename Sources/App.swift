import AppKit
import Carbon
import SwiftUI

final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = SearchModel()
    private var panel: SearchPanel!
    private var statusItem: NSStatusItem!
    private var hotkey: EventHotKeyRef?
    private var keyMonitor: Any?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = SearchPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 500),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.title = "Ego 标签搜索"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: SearchView(model: model))
        model.dismiss = { [weak self] in self?.panel.orderOut(nil) }
        setupMainMenu()
        setupMenu()
        if !model.isDemo { setupHotkey() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            let composing = (self.panel.firstResponder as? NSTextView)?.hasMarkedText() ?? false
            guard !composing else { return event }
            switch event.keyCode {
            case 53: self.panel.orderOut(nil); return nil
            case 125: self.model.move(1); return nil
            case 126: self.model.move(-1); return nil
            default: return event
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self, self.panel.isVisible else { return }
            self.model.refresh()
        }
        show()
    }

    private func setupMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出标签搜索", action: #selector(quitApp), keyEquivalent: "q").target = self
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.stack.badge.magnifyingglass", accessibilityDescription: "Ego 标签搜索")
        if statusItem.button?.image == nil { statusItem.button?.title = "Ego" }
        let menu = NSMenu()
        let open = NSMenuItem(title: "搜索标签页", action: #selector(show), keyEquivalent: "k")
        open.keyEquivalentModifierMask = [.command, .shift]
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出标签搜索", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func setupHotkey() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            delegate.toggle()
            return noErr
        }, 1, &event, pointer, nil)
        let identifier = EventHotKeyID(signature: 0x45545352, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_K), UInt32(cmdKey | shiftKey), identifier, GetApplicationEventTarget(), 0, &hotkey)
        if status != noErr {
            model.message = "⌘⇧K 已被其他应用占用。可以从菜单栏打开搜索。"
        }
    }

    @objc func show() {
        if let screen = NSScreen.main {
            let rect = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: rect.midX - 340, y: rect.maxY - 140 - 500))
        }
        model.query = ""
        model.selected = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .paletteFocus, object: nil)
        model.refresh()
    }

    func toggle() { panel.isVisible ? panel.orderOut(nil) : show() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return false
    }
    func windowDidResignKey(_ notification: Notification) { if !model.activating { panel.orderOut(nil) } }

    @objc private func quitApp() { NSApp.terminate(nil) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        panel.orderOut(nil)
        timer?.invalidate()
        if model.isDemo { return .terminateNow }
        model.bridge.send(BridgeRequest(action: "finish")) { _ in NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
}

@main
struct Startup {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
