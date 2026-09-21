import Foundation
import PingviLink
import WatchConnectivity

final class PhoneWatchBridge: NSObject, WCSessionDelegate {
    var onReply: ((PingviReply, @escaping (String) -> Void) -> Void)?
    private var latestSnapshot = PingviSnapshot(revision: 0, questions: [])
    private var latestConnection = PingviConnectionState.stopped

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func update(snapshot: PingviSnapshot, connection: PingviConnectionState) {
        let watchSnapshot = PingviSnapshot(
            revision: snapshot.revision,
            generatedAt: snapshot.generatedAt,
            questions: snapshot.questions,
            completions: snapshot.completions
        )
        latestSnapshot = watchSnapshot
        latestConnection = connection
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        guard let data = try? JSONEncoder().encode(watchSnapshot) else { return }
        try? WCSession.default.updateApplicationContext([
            "snapshot": data,
            "connected": connection == .connected
        ])
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let data = message["reply"] as? Data,
              let reply = try? JSONDecoder().decode(PingviReply.self, from: data) else {
            replyHandler(["message": "Некорректный ответ"])
            return
        }
        onReply?(reply) { message in replyHandler(["message": message]) }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated { update(snapshot: latestSnapshot, connection: latestConnection) }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
