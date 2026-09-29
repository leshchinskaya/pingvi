import Foundation
import PingviLink

enum MobileTab: Hashable {
    case queue
    case dialogs
    case settings
}

enum MobileDestination: Hashable {
    case question(PingviQuestion)
    case conversation(PingviSessionSummary)
}

/// Single source of truth for tab selection and per-tab navigation stacks, so
/// notifications, widgets and the Watch can open a screen without touching views.
@MainActor
final class MobileRouter: ObservableObject {
    static let shared = MobileRouter()

    @Published var tab: MobileTab = .queue
    @Published var queuePath: [MobileDestination] = []
    @Published var dialogsPath: [MobileDestination] = []

    init() {
#if DEBUG
        if MobileDocumentationPreview.isEnabled {
            tab = MobileDocumentationPreview.initialTab
            if MobileDocumentationPreview.screen == .conversation,
               let session = MobileDocumentationPreview.snapshot.sessions.first(where: { $0.id == MobileDocumentationPreview.conversationSessionID }) {
                queuePath = [.conversation(session)]
            }
        }
#endif
    }

    /// Pushes a destination on top of the given tab's stack and switches to that tab.
    func push(_ destination: MobileDestination, in tab: MobileTab) {
        switch tab {
        case .queue: queuePath.append(destination)
        case .dialogs: dialogsPath.append(destination)
        case .settings: break
        }
        self.tab = tab
    }

    /// Replaces the tab's stack with a single destination, used when opening a screen from outside the app.
    func open(_ destination: MobileDestination, in tab: MobileTab) {
        switch tab {
        case .queue: queuePath = [destination]
        case .dialogs: dialogsPath = [destination]
        case .settings: break
        }
        self.tab = tab
    }

    func reset() {
        tab = .queue
        queuePath = []
        dialogsPath = []
    }
}
