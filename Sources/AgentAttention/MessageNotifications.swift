import UserNotifications
import Foundation

enum MessageNotifications {
    // System notifications use the registered application icon.
    static func send(_ content: UNMutableNotificationContent, identifier: String, conversation: String, completion: ((Error?) -> Void)? = nil) {
        content.threadIdentifier = conversation
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) { error in
            let diagnostic: [String: Any] = [
                "iconSource": "applicationBundle",
                "requestAccepted": error == nil,
                "visualVerification": "required",
                "error": error?.localizedDescription ?? "",
                "time": Date().timeIntervalSince1970
            ]
            if let data = try? JSONSerialization.data(withJSONObject: diagnostic) {
                try? data.write(to: Bridge.root.appendingPathComponent("notification-status.json"), options: .atomic)
            }
            completion?(error)
        }
    }
}
