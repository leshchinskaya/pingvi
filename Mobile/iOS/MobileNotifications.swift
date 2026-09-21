import Foundation
import PingviLink
import UIKit
import UserNotifications

final class MobileAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var model: MobileAppModel?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        let info = response.notification.request.content.userInfo
        guard let sessionID = info["sessionID"] as? String,
              let token = info["token"] as? String else { return }
        var answer = ""
        if let text = response as? UNTextInputNotificationResponse {
            answer = text.userText
        } else if response.actionIdentifier.hasPrefix("option."),
                  let index = Int(response.actionIdentifier.dropFirst("option.".count)),
                  let options = info["options"] as? [String], options.indices.contains(index) {
            answer = options[index]
        } else {
            return
        }
        Task { @MainActor [weak self] in
            let model = self?.model ?? MobileAppModel.shared
            _ = model.send(PingviReply(sessionID: sessionID, questionToken: token, answer: answer))
        }
    }
}

final class MobileNotifications {
    static let shared = MobileNotifications()
    private let center = UNUserNotificationCenter.current()
    private var categories: [String: UNNotificationCategory] = [:]

    private init() {}

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func show(question: PingviQuestion) {
        let categoryID = "pingvi.question." + String(question.token.hashValue)
        var actions: [UNNotificationAction] = []
        if question.canReply && question.fields.isEmpty {
            actions = question.options.prefix(3).enumerated().map { index, option in
                UNNotificationAction(identifier: "option.\(index)", title: option.label)
            }
            actions.append(UNTextInputNotificationAction(
                identifier: "text",
                title: "Ответить",
                options: [],
                textInputButtonTitle: "Отправить",
                textInputPlaceholder: "Короткий ответ"
            ))
        }
        categories[categoryID] = UNNotificationCategory(
            identifier: categoryID,
            actions: actions,
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Агент ждёт ответа",
            categorySummaryFormat: "%u вопросов",
            options: [.hiddenPreviewsShowTitle]
        )
        center.setNotificationCategories(Set(categories.values))

        let content = UNMutableNotificationContent()
        content.title = question.title
        content.subtitle = question.agent + " · " + question.source
        content.body = UserDefaults.standard.bool(forKey: "fullNotificationPreviews") ? question.question : "Агент ждёт ответа"
        content.sound = .default
        content.threadIdentifier = question.id
        content.categoryIdentifier = categoryID
        content.userInfo = [
            "sessionID": question.id,
            "token": question.token,
            "options": question.options.map(\.replyValue)
        ]
        center.add(UNNotificationRequest(identifier: "question:\(question.id):\(question.token)", content: content, trigger: nil))
    }

    func show(completion: PingviCompletion) {
        let content = UNMutableNotificationContent()
        content.title = completion.title
        content.subtitle = completion.agent + " · " + completion.source
        content.body = "Агент закончил ответ"
        content.sound = .default
        content.threadIdentifier = completion.id
        center.add(UNNotificationRequest(identifier: "done:\(completion.id):\(completion.completedAt.timeIntervalSince1970)", content: content, trigger: nil))
    }
}
