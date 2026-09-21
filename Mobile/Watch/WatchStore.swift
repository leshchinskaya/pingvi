import Foundation
import OSLog
import PingviLink
import WatchConnectivity
import WatchKit

final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var snapshot = PingviSnapshot(revision: 0, questions: [])
    @Published private(set) var connected = false
    @Published var message: String?

    private let cacheURL: URL
    private let logger = Logger(subsystem: "app.pingvi.watch", category: "Connectivity")

    override init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        cacheURL = base.appendingPathComponent("Pingvi/watch-snapshot.json")
        super.init()
        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode(PingviSnapshot.self, from: data) {
            snapshot = cached
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    var questions: [PingviQuestion] { snapshot.questions.sorted { $0.arrivedAt < $1.arrivedAt } }

    func send(question: PingviQuestion, answer: String, fieldAnswers: [String: String] = [:]) {
        guard connected, WCSession.default.isReachable else {
            logger.info("Reply rejected while phone is unreachable")
            message = "Откройте Pingvi на iPhone и проверьте соединение с Mac."
            WKInterfaceDevice.current().play(.failure)
            return
        }
        let reply = PingviReply(
            sessionID: question.id,
            questionToken: question.token,
            answer: answer,
            fieldAnswers: fieldAnswers
        )
        guard let data = try? JSONEncoder().encode(reply) else { return }
        message = "Отправляем…"
        WCSession.default.sendMessage(["reply": data], replyHandler: { [weak self] response in
            DispatchQueue.main.async {
                self?.message = response["message"] as? String ?? "Отправлено"
                WKInterfaceDevice.current().play(.success)
            }
        }, errorHandler: { [weak self] error in
            DispatchQueue.main.async {
                self?.message = "Результат неизвестен: \(error.localizedDescription)"
                WKInterfaceDevice.current().play(.failure)
            }
        })
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["snapshot"] as? Data,
              let value = try? JSONDecoder().decode(PingviSnapshot.self, from: data) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            snapshot = value
            connected = applicationContext["connected"] as? Bool ?? false
            logger.debug("Received revision \(value.revision, privacy: .public), pending \(value.questions.count, privacy: .public)")
            persist(value)
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.connected = activationState == .activated && session.isReachable
            if let error { self?.message = error.localizedDescription }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in self?.connected = session.isReachable }
    }

    private func persist(_ value: PingviSnapshot) {
        do {
            let directory = cacheURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: cacheURL, options: [.atomic, .completeFileProtection])
        } catch {
            message = "Не удалось сохранить очередь."
        }
    }
}
