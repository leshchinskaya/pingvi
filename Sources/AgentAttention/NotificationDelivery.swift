import Foundation
import Combine
import UserNotifications

struct NotificationAccess: Equatable {
    var authorization: UNAuthorizationStatus
    var alerts: Bool
    var banners: Bool
    var center: Bool

    init(_ settings: UNNotificationSettings) {
        authorization = settings.authorizationStatus
        alerts = settings.alertSetting == .enabled
        banners = settings.alertStyle != .none
        center = settings.notificationCenterSetting == .enabled
    }
    init(authorization: UNAuthorizationStatus, alerts: Bool = true, banners: Bool = true, center: Bool = true) {
        self.authorization = authorization; self.alerts = alerts; self.banners = banners; self.center = center
    }
    var permitted: Bool { [.authorized, .provisional].contains(authorization) }
    var canShowBanner: Bool { permitted && authorization != .provisional && alerts && banners }
    var summary: String {
        if authorization == .notDetermined { return "Разрешение ещё не запрошено" }
        if !permitted { return "Уведомления запрещены" }
        if canShowBanner { return "Баннеры включены" }
        return center ? "Только Центр уведомлений" : "Показ уведомлений выключен"
    }
    var guidance: String {
        if authorization == .notDetermined { return "Нажмите «Разрешить уведомления» и подтвердите запрос macOS." }
        if !permitted { return "В настройках macOS → Уведомления → Pingvi включите «Допуск уведомлений»." }
        if !canShowBanner { return "В настройках macOS → Уведомления → Pingvi включите показ и выберите стиль «Баннеры» или «Предупреждения»." }
        return "Если баннеров нет, проверьте «Фокусирование» и разрешение уведомлений при дублировании экрана в настройках macOS."
    }
}

protocol NotificationTransport {
    func settings(_ completion: @escaping (NotificationAccess) -> Void)
    func authorize(_ completion: @escaping (Bool, Error?) -> Void)
    func add(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void)
}

struct SystemNotificationTransport: NotificationTransport {
    func settings(_ completion: @escaping (NotificationAccess) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { completion(NotificationAccess($0)) }
    }
    func authorize(_ completion: @escaping (Bool, Error?) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge], completionHandler: completion)
    }
    func add(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void) {
        UNUserNotificationCenter.current().add(request, withCompletionHandler: completion)
    }
}

final class NotificationDelivery: ObservableObject {
    @Published private(set) var access: NotificationAccess?
    @Published private(set) var lastResult: String?
    private let transport: NotificationTransport
    private var resolving = false
    private var pending: [(UNNotificationRequest, (Error?) -> Void)] = []
    init(transport: NotificationTransport = SystemNotificationTransport()) { self.transport = transport }

    func send(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void) {
        pending.append((request, completion))
        requestPermission()
    }

    func refresh() {
        transport.settings { [weak self] settings in
            DispatchQueue.main.async { self?.access = settings }
        }
    }

    func requestPermission() {
        guard !resolving else { return }
        resolving = true
        transport.settings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self else { return }
                self.access = settings
                if settings.authorization == .notDetermined {
                    self.transport.authorize { [weak self] granted, error in
                        guard let self else { return }
                        self.transport.settings { settings in
                            DispatchQueue.main.async {
                                self.finish(settings, error: error ?? (granted ? nil : Self.failure("Разрешите уведомления Pingvi в настройках macOS → Уведомления.")))
                            }
                        }
                    }
                } else { self.finish(settings, error: nil) }
            }
        }
    }

    private static func failure(_ text: String) -> Error {
        NSError(domain: "PingviNotifications", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }

    private func finish(_ settings: NotificationAccess, error: Error?) {
        access = settings
        resolving = false
        let jobs = pending; pending = []
        let blocked = error ?? (!settings.permitted || (!settings.canShowBanner && !settings.center) ? Self.failure(settings.guidance) : nil)
        if let blocked {
            lastResult = blocked.localizedDescription
            jobs.forEach { $0.1(blocked) }
            return
        }
        if jobs.isEmpty { lastResult = nil }
        for (request, completion) in jobs {
            transport.add(request) { [weak self] error in
                DispatchQueue.main.async {
                    self?.lastResult = error.map { "macOS отклонила уведомление: " + $0.localizedDescription }
                        ?? (settings.canShowBanner ? "Запрос передан macOS. Проверьте появление баннера." : "Запрос передан macOS; баннеры выключены. Проверьте Центр уведомлений.")
                    completion(error)
                }
            }
        }
    }
}
