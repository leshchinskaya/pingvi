import UserNotifications
import Foundation

enum MessageNotifications {
    static let delivery = NotificationDelivery()
    // System notifications use the registered application icon.
    static func send(_ content: UNMutableNotificationContent, identifier: String, conversation: String, completion: ((Error?) -> Void)? = nil) {
        guard !Installation.needsMove() else {
            completion?(NSError(domain: "PingviInstallation", code: 1, userInfo: [NSLocalizedDescriptionKey: Installation.message]))
            return
        }
        content.threadIdentifier = conversation
        delivery.send(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) { error in
            var diagnostic: [String: Any] = [
                "iconSource": "applicationBundle",
                "requestAccepted": error == nil,
                "visualVerification": "required",
                "error": error?.localizedDescription ?? "",
                "time": Date().timeIntervalSince1970
            ]
            if let access = delivery.access {
                diagnostic["authorization"] = access.authorization.rawValue
                diagnostic["alertsEnabled"] = access.alerts
                diagnostic["bannersEnabled"] = access.canShowBanner
                diagnostic["notificationCenterEnabled"] = access.center
            }
            if let data = try? JSONSerialization.data(withJSONObject: diagnostic) {
                let path = Bridge.root.appendingPathComponent("notification-status.json")
                try? FileManager.default.createDirectory(at: Bridge.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try? data.write(to: path, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
            }
            completion?(error)
        }
    }
}
