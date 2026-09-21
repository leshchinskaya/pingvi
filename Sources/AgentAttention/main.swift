import AppKit
import SwiftUI
import UserNotifications
import ApplicationServices
import Combine

final class HoverArea: NSView {
    var enter: (() -> Void)?
    var click: (() -> Void)?
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { enter?() }
    override func mouseDown(with event: NSEvent) { click?() }
}
final class QuestionPanel: NSPanel { override var canBecomeKey: Bool { true } }
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let store = Store()
    lazy var mobileLink = MacMobileLink(store: store)
    var window: NSWindow!
    var settingsWindow: NSWindow?
    var status: NSStatusItem!
    let popover = NSPopover()
    var panel: QuestionPanel?
    var panelSession: String?
    var dockPanel: QuestionPanel?
    var dockTimer: Timer?
    var lastDockHover = Date.distantPast
    var renderedIndicator = ""
    var moodSubscription: AnyCancellable?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        refreshTheme()
        IconAppearance.shared.start()
        let menu = NSMenu(), appMenu = NSMenu(), item = NSMenuItem()
        appMenu.addItem(withTitle: "Открыть Pingvi", action: #selector(showWindow), keyEquivalent: "0")
        appMenu.addItem(withTitle: "Настройки…", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: "Завершить", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu; menu.addItem(item)
        let edit = NSMenu(title: "Правка"), editItem = NSMenuItem(title: "Правка", action: nil, keyEquivalent: "")
        for (title, selector, key) in [("Вырезать", "cut:", "x"), ("Копировать", "copy:", "c"), ("Вставить", "paste:", "v"), ("Выбрать всё", "selectAll:", "a")] { edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key) }
        editItem.submenu = edit; menu.addItem(editItem); NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.title = "Pingvi"; window.minSize = NSSize(width: 720, height: 540); window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView(store: store, chatUpdatesEnabled: { [weak self] in
            self?.canRefreshMainChat() == true
        }))
        if !window.setFrameUsingName("AgentAttentionMain") { window.center() }
        window.setFrameAutosaveName("AgentAttentionMain")
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = status.button {
            let area = HoverArea(frame: button.bounds); area.autoresizingMask = [.width, .height]
            area.enter = { [weak self] in self?.showPopover() }
            area.click = { [weak self] in
                guard let self else { return }
                if self.popover.isShown { self.popover.performClose(nil) } else { self.showPopover() }
            }
            button.addSubview(area)
        }
        popover.contentSize = NSSize(width: 460, height: 700); popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ContentView(
            store: store,
            compact: true,
            onClose: { [weak self] in self?.popover.performClose(nil) },
            chatUpdatesEnabled: { [weak self] in self?.popover.isShown == true }
        ))
        store.showSettings = { [weak self] in self?.showSettings() }
        store.onChange = { [weak self] in
            self?.refresh()
            self?.mobileLink.storeDidChange()
        }
        moodSubscription = IconAppearance.shared.$selected.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }
        store.showDashboard = { [weak self] in self?.popover.performClose(nil); self?.dockPanel?.orderOut(nil); self?.showWindow() }
        store.showQuestion = { [weak self] id in self?.showPanel(id) }
        store.closeQuestion = { [weak self] in self?.panel?.orderOut(nil); self?.panelSession = nil; self?.popover.performClose(nil) }
        UNUserNotificationCenter.current().delegate = self
        if !Installation.needsMove() { MessageNotifications.delivery.requestPermission() }
        mobileLink.start()
        refresh(); showWindow(); store.start()
        if CommandLine.arguments.contains("--show-settings") { showSettings() }
        if CommandLine.arguments.contains("--test-notification") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.store.testNotification() }
        }
        dockTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.checkDockHover() }
        // Export only this app's own view for development smoke checks.
        if let index = CommandLine.arguments.firstIndex(of: "--capture"), CommandLine.arguments.count > index + 1 {
            let path = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
                guard let self, let view = (self.settingsWindow?.isVisible == true ? self.settingsWindow : self.window)?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                do {
                    let compact = NSHostingView(rootView: ContentView(store: self.store, compact: true, onClose: {}))
                    compact.frame = NSRect(x: 0, y: 0, width: 460, height: 680)
                    compact.layoutSubtreeIfNeeded()
                    if let image = compact.bitmapImageRepForCachingDisplay(in: compact.bounds) {
                        compact.cacheDisplay(in: compact.bounds, to: image)
                        try? image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("compact.png"))
                    }
                }
            }
        }
    }
    @objc func showSettings() {
        popover.performClose(nil); dockPanel?.orderOut(nil)
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 620), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.title = "Настройки — Pingvi"; w.minSize = NSSize(width: 760, height: 540)
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(store: store, mobileLink: mobileLink))
            w.center(); w.setFrameAutosaveName("PingviSettings")
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func showPopover() {
        guard !popover.isShown, let button = status.button else { return }
        popover.contentSize.height = min(700, max(420, (button.window?.screen?.visibleFrame.height ?? 770) - 70))
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    func canRefreshMainChat() -> Bool {
        ChatRefreshPolicy.allowsMainWindow(appIsActive: NSApp.isActive, window: window)
    }
    func refreshTheme() {
        let appearance = AppTheme.saved().appearance
        if NSApp.appearance?.name != appearance?.name { NSApp.appearance = appearance }
        // The popover is anchored to the system menu bar, which can use a different theme.
        if popover.appearance?.name != appearance?.name { popover.appearance = appearance }
    }
    func checkDockHover() {
        guard UserDefaults.standard.bool(forKey: "dock"), AXIsProcessTrusted() else { return }
        let point = NSEvent.mouseLocation
        if dockPanel?.isVisible == true, dockPanel!.frame.contains(point) { lastDockHover = Date(); return }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
        var element: AXUIElement?
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let result = AXUIElementCopyElementAtPosition(AXUIElementCreateApplication(dock.processIdentifier), Float(point.x), Float(top - point.y), &element)
        var hovered = false
        if result == .success, var e = element {
            for _ in 0..<4 {
                var title: CFTypeRef?, role: CFTypeRef?
                AXUIElementCopyAttributeValue(e, kAXTitleAttribute as CFString, &title)
                AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &role)
                if (title as? String) == "Pingvi", (role as? String) == "AXDockItem" { hovered = true; break }
                var parent: CFTypeRef?
                guard AXUIElementCopyAttributeValue(e, kAXParentAttribute as CFString, &parent) == .success, let p = parent else { break }
                e = (p as! AXUIElement)
            }
        }
        if hovered {
            lastDockHover = Date()
            if dockPanel == nil {
                dockPanel = QuestionPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 680), styleMask: [.nonactivatingPanel, .titled, .closable, .miniaturizable], backing: .buffered, defer: false)
                dockPanel?.isReleasedWhenClosed = false
                dockPanel?.title = "Pingvi · Сессии"; dockPanel?.level = .floating; dockPanel?.hidesOnDeactivate = false
                dockPanel?.contentView = NSHostingView(rootView: ContentView(
                    store: store,
                    compact: true,
                    onClose: { [weak self] in self?.dockPanel?.orderOut(nil) },
                    chatUpdatesEnabled: { [weak self] in self?.dockPanel?.isVisible == true }
                ))
                dockPanel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            }
            if dockPanel?.isVisible != true, let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
                let f = screen.visibleFrame
                dockPanel?.setFrameOrigin(NSPoint(x: min(max(point.x - 230, f.minX), f.maxX - 460), y: min(max(point.y + 25, f.minY), f.maxY - 680)))
                dockPanel?.orderFrontRegardless()
            }
        } else if Date().timeIntervalSince(lastDockHover) > 0.8, dockPanel?.isKeyWindow != true { dockPanel?.orderOut(nil) }
    }
    func showPanel(_ id: String, switching: Bool = false) {
        guard switching || !NSApp.isActive || panel?.isVisible == true else { return }
        if !switching, panel?.isVisible == true, let active = panelSession, store.visible.contains(where: { $0.id == active && store.needsAttention($0) }) { return }
        guard let s = store.visible.first(where: { $0.id == id }) else { return }
        panelSession = id
        if panel == nil {
            panel = QuestionPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 550), styleMask: [.titled, .nonactivatingPanel, .resizable, .closable, .miniaturizable], backing: .buffered, defer: false)
            panel?.title = "Pingvi"; panel?.level = .floating; panel?.hidesOnDeactivate = false
            panel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel?.isReleasedWhenClosed = false
        }
        panel?.contentView = NSHostingView(rootView: FloatingQuestion(store: store, id: s.id, selectQuestion: { [weak self] id in self?.showPanel(id, switching: true) }))
        if !switching, let screen = NSScreen.main { let f = screen.visibleFrame; panel?.setFrameOrigin(NSPoint(x: f.maxX - 464, y: f.maxY - 590)) }
        panel?.orderFrontRegardless()
    }
    func refresh() {
        refreshTheme()
        let count = store.pending.count
        let dockCount = store.pending.filter { $0.status == "waiting" }.count
        let dockVisible = UserDefaults.standard.bool(forKey: "dock")
        let menuVisible = UserDefaults.standard.bool(forKey: "menubar")
        let indicator = "\(store.aggregate):\(count):\(dockCount):\(dockVisible):\(menuVisible):\(IconAppearance.shared.selected.rawValue)"
        if indicator != renderedIndicator {
        renderedIndicator = indicator
        let color = NSColor(stateColor(store.aggregate))
        status?.button?.image = Brand.menuIcon
        let title = NSMutableAttributedString(string: " ●", attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 10)])
        if count > 0 { title.append(NSAttributedString(string: " \(count)", attributes: [.foregroundColor: NSColor.labelColor, .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)])) }
        status?.button?.attributedTitle = title
        status?.button?.toolTip = count > 0 ? "Pingvi · Ждут ответа: \(count)" : "Pingvi · Вопросы ваших агентов"
        status?.isVisible = menuVisible
        let policy: NSApplication.ActivationPolicy = dockVisible ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
        NSApp.dockTile.badgeLabel = dockCount > 0 ? String(dockCount) : nil
        let dockView = NSHostingView(rootView: ZStack(alignment: .topTrailing) {
            Image(nsImage: Brand.dockIcon).resizable().scaledToFit()
            if dockCount > 0 {
                Circle().fill(stateColor("waiting")).frame(width: 23, height: 23)
                    .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 3)).padding(7)
            }
        })
        NSApp.dockTile.contentView = dockView; NSApp.dockTile.display()
        }
        if let id = panelSession, !store.visible.contains(where: { $0.id == id && store.needsAttention($0) }) {
            panel?.orderOut(nil); panelSession = nil
            if UserDefaults.standard.bool(forKey: "floating"), let next = store.pending.first(where: { !store.local.dismissed.contains($0.token) }) { showPanel(next.id) }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .list]) }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            if let id = response.notification.request.content.userInfo["session"] as? String {
                if let session = self.store.visible.first(where: { $0.id == id }) { self.store.choose(session) }
                if response.notification.request.content.userInfo["kind"] as? String == "done", let s = self.store.current { self.store.open(s) }
                else { self.showWindow() }
            } else { self.showWindow() }
            completionHandler()
        }
    }
}
struct FloatingQuestion: View {
    @ObservedObject var store: Store
    let id: String
    var selectQuestion: ((String) -> Void)? = nil
    var body: some View {
        VStack(spacing: 0) {
            if let s = store.visible.first(where: { $0.id == id }) {
                QuestionView(store: store, session: s, compact: true, selectQuestion: selectQuestion)
                    .id(s.id)
            }
        }.padding(16).frame(minWidth: 380, minHeight: 450).background { AmbientBackground() }.tint(Palette.accent)
    }
}

if let index = CommandLine.arguments.firstIndex(of: "--preview-floating"), CommandLine.arguments.count > index + 1 {
    do { try ReleasePreview.captureDashboard(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), floating: true, dark: CommandLine.arguments.contains("--preview-dark"), approval: CommandLine.arguments.contains("--preview-approval")); exit(0) }
    catch { FileHandle.standardError.write(Data(error.localizedDescription.utf8)); exit(1) }
}
if let index = CommandLine.arguments.firstIndex(of: "--preview-dashboard"), CommandLine.arguments.count > index + 1 {
    do { try ReleasePreview.captureDashboard(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), dark: CommandLine.arguments.contains("--preview-dark"), settings: CommandLine.arguments.contains("--preview-settings")); exit(0) }
    catch { FileHandle.standardError.write(Data(error.localizedDescription.utf8)); exit(1) }
}
if let index = CommandLine.arguments.firstIndex(of: "--preview-data"), CommandLine.arguments.count > index + 1 {
    do { try ReleasePreview.captureData(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])); exit(0) }
    catch { FileHandle.standardError.write(Data(error.localizedDescription.utf8)); exit(1) }
}
if CommandLine.arguments.contains("--check-installation") {
    print(Installation.needsMove() ? "move-required" : "location-ok")
    exit(0)
}
// Release smoke check: no windows, preferences, agents or user data are touched.
if CommandLine.arguments.contains("--check-runtime") {
    do {
        let data = try BridgeProcess.run(executable: Bridge.python, arguments: ["-E", "-s", "-B", Bridge.script], input: Data("{\"action\":\"runtime-check\"}".utf8), timeout: 10)
        FileHandle.standardOutput.write(data)
        exit(0)
    } catch {
        FileHandle.standardError.write(Data(error.localizedDescription.utf8))
        exit(1)
    }
}
PreferenceMigration.run()
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
