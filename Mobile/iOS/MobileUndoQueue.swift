import Foundation
import PingviLink

/// Holds one-tap replies for a short grace period so an accidental tap can be undone
/// before anything reaches the Mac.
@MainActor
final class MobileUndoQueue: ObservableObject {
    struct Pending: Equatable {
        let reply: PingviReply
        let label: String
        let deadline: Date
    }

    @Published private(set) var pending: [String: Pending] = [:]

    let delay: Duration
    private var tasks: [String: Task<Void, Never>] = [:]

    init(delay: Duration = .seconds(3)) {
        self.delay = delay
    }

    /// Schedules `commit` after the grace period unless `cancel` is called first.
    /// A new reply for the same session replaces the previous one.
    func schedule(_ reply: PingviReply, label: String, now: Date = Date(), commit: @escaping @MainActor (PingviReply) -> Void) {
        let sessionID = reply.sessionID
        tasks[sessionID]?.cancel()
        let seconds = Double(delay.components.seconds) + Double(delay.components.attoseconds) / 1e18
        pending[sessionID] = Pending(reply: reply, label: label, deadline: now.addingTimeInterval(seconds))
        tasks[sessionID] = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, let item = self.pending[sessionID], item.reply == reply else { return }
            self.pending[sessionID] = nil
            self.tasks[sessionID] = nil
            commit(item.reply)
        }
    }

    func cancel(sessionID: String) {
        tasks.removeValue(forKey: sessionID)?.cancel()
        pending[sessionID] = nil
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        pending = [:]
    }
}
