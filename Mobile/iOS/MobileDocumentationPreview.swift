#if DEBUG
import Foundation
import PingviLink

enum MobileDocumentationPreview {
    enum Screen: String {
        case queue
        case dialogs
        case conversation
        case appearance
    }

    static let conversationSessionID = "demo-completed"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--documentation-preview")
    }

    static var screen: Screen {
        let arguments = ProcessInfo.processInfo.arguments
        guard let marker = arguments.firstIndex(of: "--documentation-screen"),
              arguments.indices.contains(marker + 1),
              let screen = Screen(rawValue: arguments[marker + 1]) else {
            return .queue
        }
        return screen
    }

    static var initialTab: Int {
        switch screen {
        case .queue, .conversation: return 0
        case .dialogs: return 1
        case .appearance: return 2
        }
    }

    static let pairing = PingviPairingRecord(
        serviceID: "documentation-preview",
        localDeviceID: "demo-phone",
        peerDeviceID: "demo-mac",
        peerName: "MacBook Pro",
        pairingKey: Data(repeating: 7, count: 32),
        createdAt: Date(timeIntervalSince1970: 1_789_989_600)
    )

    static let snapshot: PingviSnapshot = {
        let now = Date()
        let waiting = PingviSessionSummary(
            id: "demo-permission",
            title: "Проверка сборки",
            project: "Pingvi",
            projectPath: "/Projects/Pingvi",
            agent: "codex",
            source: "herdr",
            status: "waiting",
            preview: "Нужно разрешение на запуск тестов интерфейса.",
            updatedAt: now.addingTimeInterval(-75)
        )
        let completed = PingviSessionSummary(
            id: conversationSessionID,
            title: "Уведомления на устройствах",
            project: "Pingvi",
            projectPath: "/Projects/Pingvi",
            agent: "codex",
            source: "herdr",
            status: "done",
            preview: "Готово: добавлена доставка на iPhone и Apple Watch.",
            updatedAt: now.addingTimeInterval(-420)
        )
        let working = PingviSessionSummary(
            id: "demo-working",
            title: "Обновление сайта",
            project: "Landing",
            projectPath: "/Projects/Landing",
            agent: "claude",
            source: "Claude Code",
            status: "working",
            preview: "Обновляю адаптивную вёрстку и проверяю мобильную версию.",
            updatedAt: now.addingTimeInterval(-900)
        )
        return PingviSnapshot(
            revision: 42,
            generatedAt: now,
            questions: [
                PingviQuestion(
                    id: waiting.id,
                    token: "demo-question-token",
                    title: "Проверка сборки",
                    project: waiting.project,
                    agent: "codex",
                    source: "herdr",
                    question: "Разрешить запуск тестов интерфейса на этом Mac?",
                    context: "Агент подготовил изменения и хочет проверить их перед завершением.",
                    options: [
                        PingviOption(id: "yes", label: "Да"),
                        PingviOption(id: "always", label: "Да, и больше не спрашивать"),
                        PingviOption(id: "no", label: "Нет")
                    ],
                    fields: [],
                    state: .waiting,
                    canReply: true,
                    arrivedAt: now.addingTimeInterval(-75)
                )
            ],
            completions: [
                PingviCompletion(
                    id: completed.id,
                    title: completed.title,
                    agent: completed.agent,
                    source: completed.source,
                    summary: completed.preview,
                    completedAt: now.addingTimeInterval(-420)
                )
            ],
            sessions: [waiting, completed, working],
            projects: [
                PingviProject(name: "Pingvi", path: "/Projects/Pingvi"),
                PingviProject(name: "Landing", path: "/Projects/Landing")
            ]
        )
    }()

    static let conversations: [String: PingviConversation] = [
        conversationSessionID: PingviConversation(
            sessionID: conversationSessionID,
            title: "Уведомления на устройствах",
            project: "Pingvi",
            agent: "codex",
            source: "herdr",
            status: "done",
            messages: [
                PingviChatMessage(
                    id: "demo-message-1",
                    role: .user,
                    text: "Добавь уведомления на iPhone и Apple Watch, оставив обмен данными локальным.",
                    state: .received
                ),
                PingviChatMessage(
                    id: "demo-message-2",
                    role: .assistant,
                    text: "Готово. Устройства связываются QR-кодом и обмениваются зашифрованными сообщениями в одной Wi-Fi сети.",
                    state: .received
                ),
                PingviChatMessage(
                    id: "demo-message-3",
                    role: .user,
                    text: "Добавь быстрые ответы и просмотр готовых результатов.",
                    state: .checked
                ),
                PingviChatMessage(
                    id: "demo-message-4",
                    role: .assistant,
                    text: "Добавил очередь вопросов, историю диалогов и ответы прямо с iPhone. Готовый результат можно открыть из уведомления или вкладки «Диалоги».",
                    state: .received
                )
            ],
            partial: false,
            context: "",
            canSend: true,
            busy: false,
            reason: "",
            token: "demo-conversation-token",
            pending: false
        )
    ]
}
#endif
