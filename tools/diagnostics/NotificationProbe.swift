import AppKit
import UserNotifications

final class Probe: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 180), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Pingvi Icon Test"
        let label = NSTextField(wrappingLabelWithString: "Проверка системного значка. Разрешите уведомления для Pingvi Icon Test. Тест не читает сессии и не меняет настройки Pingvi.")
        label.frame = NSRect(x: 24, y: 70, width: 372, height: 80)
        window.contentView?.addSubview(label)
        let button = NSButton(title: "Повторить уведомление", target: self, action: #selector(send))
        button.frame = NSRect(x: 100, y: 24, width: 220, height: 32)
        window.contentView?.addSubview(button)
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        send()
    }
    @objc func send() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, error in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Тест A — новая регистрация"
            content.body = "Слева должен быть синий пингвин. Это отдельное тестовое приложение."
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)))
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .list]) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
let delegate = Probe()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
