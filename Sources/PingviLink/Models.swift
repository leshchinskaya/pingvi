import Foundation

public enum PingviProtocol {
    public static let currentVersion = 2
    public static let minimumVersion = 2
    public static let serviceType = "_pingvi._tcp"
    public static let maximumFrameSize = 1_048_576
    public static let maximumTextLength = 8_192
    public static let maximumConversationMessages = 100
}

public struct PingviOption: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }

    /// The transport expects the stable option identifier, while `label` is display-only.
    public var replyValue: String { id }
}

public struct PingviQuestionField: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let options: [PingviOption]
    public let allowsMultiple: Bool

    public init(id: String, label: String, options: [PingviOption], allowsMultiple: Bool) {
        self.id = id
        self.label = label
        self.options = options
        self.allowsMultiple = allowsMultiple
    }
}

public enum PingviQuestionState: String, Codable, Sendable {
    case waiting
    case checking
    case unconfirmed
}

public struct PingviQuestion: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let token: String
    public let title: String
    public let project: String
    public let agent: String
    public let source: String
    public let question: String
    public let context: String
    public let options: [PingviOption]
    public let fields: [PingviQuestionField]
    public let state: PingviQuestionState
    public let canReply: Bool
    public let arrivedAt: Date

    public init(
        id: String,
        token: String,
        title: String,
        project: String,
        agent: String,
        source: String,
        question: String,
        context: String,
        options: [PingviOption],
        fields: [PingviQuestionField],
        state: PingviQuestionState,
        canReply: Bool,
        arrivedAt: Date
    ) {
        self.id = id
        self.token = token
        self.title = title
        self.project = project
        self.agent = agent
        self.source = source
        self.question = String(question.prefix(PingviProtocol.maximumTextLength))
        self.context = String(context.prefix(PingviProtocol.maximumTextLength))
        self.options = options
        self.fields = fields
        self.state = state
        self.canReply = canReply
        self.arrivedAt = arrivedAt
    }
}

public struct PingviCompletion: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let agent: String
    public let source: String
    public let summary: String
    public let completedAt: Date

    public init(id: String, title: String, agent: String, source: String, summary: String, completedAt: Date) {
        self.id = id
        self.title = title
        self.agent = agent
        self.source = source
        self.summary = String(summary.prefix(512))
        self.completedAt = completedAt
    }
}

public struct PingviProject: Codable, Equatable, Identifiable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String

    public init(name: String, path: String) {
        self.name = String(name.prefix(512))
        self.path = String(path.prefix(PingviProtocol.maximumTextLength))
    }
}

public struct PingviSessionSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let project: String
    public let projectPath: String
    public let agent: String
    public let source: String
    public let status: String
    public let preview: String
    public let updatedAt: Date

    public init(
        id: String,
        title: String,
        project: String,
        projectPath: String,
        agent: String,
        source: String,
        status: String,
        preview: String,
        updatedAt: Date
    ) {
        self.id = id
        self.title = String(title.prefix(512))
        self.project = String(project.prefix(512))
        self.projectPath = String(projectPath.prefix(PingviProtocol.maximumTextLength))
        self.agent = String(agent.prefix(128))
        self.source = String(source.prefix(128))
        self.status = String(status.prefix(128))
        self.preview = String(preview.prefix(1_024))
        self.updatedAt = updatedAt
    }
}

public enum PingviChatRole: String, Codable, Sendable {
    case user
    case assistant
}

public enum PingviChatMessageState: String, Codable, Sendable {
    case received
    case submitted
    case uncertain
    case checked
}

public struct PingviChatMessage: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let role: PingviChatRole
    public let text: String
    public let state: PingviChatMessageState

    public init(id: String, role: PingviChatRole, text: String, state: PingviChatMessageState) {
        self.id = id
        self.role = role
        self.text = String(text.prefix(PingviProtocol.maximumTextLength))
        self.state = state
    }
}

public struct PingviConversation: Codable, Equatable, Sendable {
    public let sessionID: String
    public let title: String
    public let project: String
    public let agent: String
    public let source: String
    public let status: String
    public let messages: [PingviChatMessage]
    public let partial: Bool
    public let context: String
    public let canSend: Bool
    public let busy: Bool
    public let reason: String
    public let token: String
    public let pending: Bool

    public init(
        sessionID: String,
        title: String,
        project: String,
        agent: String,
        source: String,
        status: String,
        messages: [PingviChatMessage],
        partial: Bool,
        context: String,
        canSend: Bool,
        busy: Bool,
        reason: String,
        token: String,
        pending: Bool
    ) {
        self.sessionID = sessionID
        self.title = String(title.prefix(512))
        self.project = String(project.prefix(512))
        self.agent = String(agent.prefix(128))
        self.source = String(source.prefix(128))
        self.status = String(status.prefix(128))
        self.messages = Array(messages.suffix(PingviProtocol.maximumConversationMessages))
        self.partial = partial || messages.count > PingviProtocol.maximumConversationMessages
        self.context = String(context.prefix(PingviProtocol.maximumTextLength))
        self.canSend = canSend
        self.busy = busy
        self.reason = String(reason.prefix(1_024))
        self.token = String(token.prefix(512))
        self.pending = pending
    }
}

public struct PingviConversationRequest: Codable, Equatable, Sendable {
    public let sessionID: String
    public init(sessionID: String) { self.sessionID = sessionID }
}

public struct PingviConversationResponse: Codable, Equatable, Sendable {
    public let requestID: String
    public let sessionID: String
    public let conversation: PingviConversation?
    public let error: String?

    public init(requestID: String, sessionID: String, conversation: PingviConversation? = nil, error: String? = nil) {
        self.requestID = requestID
        self.sessionID = sessionID
        self.conversation = conversation
        self.error = error.map { String($0.prefix(1_024)) }
    }
}

public struct PingviChatSendRequest: Codable, Equatable, Sendable {
    public let sessionID: String
    public let conversationToken: String
    public let text: String

    public init(sessionID: String, conversationToken: String, text: String) {
        self.sessionID = sessionID
        self.conversationToken = String(conversationToken.prefix(512))
        self.text = String(text.prefix(PingviProtocol.maximumTextLength))
    }
}

public enum PingviChatSendStatus: String, Codable, Sendable {
    case submitted
    case uncertain
    case stale
    case failed
}

public struct PingviChatSendResult: Codable, Equatable, Sendable {
    public let commandID: String
    public let sessionID: String
    public let status: PingviChatSendStatus
    public let message: String

    public init(commandID: String, sessionID: String, status: PingviChatSendStatus, message: String) {
        self.commandID = commandID
        self.sessionID = sessionID
        self.status = status
        self.message = String(message.prefix(1_024))
    }
}

public struct PingviCreateChatRequest: Codable, Equatable, Sendable {
    public let agent: String
    public let projectPath: String
    public let text: String

    public init(agent: String, projectPath: String, text: String) {
        self.agent = String(agent.prefix(128))
        self.projectPath = String(projectPath.prefix(PingviProtocol.maximumTextLength))
        self.text = String(text.prefix(PingviProtocol.maximumTextLength))
    }
}

public struct PingviCreateChatResult: Codable, Equatable, Sendable {
    public let commandID: String
    public let session: PingviSessionSummary?
    public let error: String?

    public init(commandID: String, session: PingviSessionSummary? = nil, error: String? = nil) {
        self.commandID = commandID
        self.session = session
        self.error = error.map { String($0.prefix(1_024)) }
    }
}

public struct PingviSnapshot: Codable, Equatable, Sendable {
    public let revision: UInt64
    public let generatedAt: Date
    public let questions: [PingviQuestion]
    public let completions: [PingviCompletion]
    public let sessions: [PingviSessionSummary]
    public let projects: [PingviProject]

    public init(
        revision: UInt64,
        generatedAt: Date = Date(),
        questions: [PingviQuestion],
        completions: [PingviCompletion] = [],
        sessions: [PingviSessionSummary] = [],
        projects: [PingviProject] = []
    ) {
        self.revision = revision
        self.generatedAt = generatedAt
        self.questions = questions
        self.completions = completions
        self.sessions = sessions
        self.projects = projects
    }
}

public struct PingviReply: Codable, Equatable, Sendable {
    public let sessionID: String
    public let questionToken: String
    public let answer: String
    public let fieldAnswers: [String: String]

    public init(sessionID: String, questionToken: String, answer: String, fieldAnswers: [String: String] = [:]) {
        self.sessionID = sessionID
        self.questionToken = questionToken
        self.answer = String(answer.prefix(PingviProtocol.maximumTextLength))
        self.fieldAnswers = fieldAnswers.mapValues { String($0.prefix(PingviProtocol.maximumTextLength)) }
    }
}

public enum PingviReplyStatus: String, Codable, Sendable {
    case checking
    case accepted
    case stale
    case unavailable
    case uncertain
    case failed

    public var keepsSubmissionPending: Bool { self == .checking }
}

public struct PingviReplyResult: Codable, Equatable, Sendable {
    public let commandID: String
    public let status: PingviReplyStatus
    public let message: String

    public init(commandID: String, status: PingviReplyStatus, message: String) {
        self.commandID = commandID
        self.status = status
        self.message = String(message.prefix(512))
    }
}

public enum PingviMessageKind: String, Codable, Sendable {
    case requestSnapshot
    case snapshot
    case reply
    case replyResult
    case requestConversation
    case conversation
    case chatSend
    case chatSendResult
    case createChat
    case createChatResult
    case ping
    case pong
}

public struct PingviMessage: Codable, Equatable, Sendable {
    public let version: Int
    public let id: String
    public let kind: PingviMessageKind
    public let snapshot: PingviSnapshot?
    public let reply: PingviReply?
    public let replyResult: PingviReplyResult?
    public let conversationRequest: PingviConversationRequest?
    public let conversationResponse: PingviConversationResponse?
    public let chatSendRequest: PingviChatSendRequest?
    public let chatSendResult: PingviChatSendResult?
    public let createChatRequest: PingviCreateChatRequest?
    public let createChatResult: PingviCreateChatResult?

    public init(
        version: Int = PingviProtocol.currentVersion,
        id: String = UUID().uuidString,
        kind: PingviMessageKind,
        snapshot: PingviSnapshot? = nil,
        reply: PingviReply? = nil,
        replyResult: PingviReplyResult? = nil,
        conversationRequest: PingviConversationRequest? = nil,
        conversationResponse: PingviConversationResponse? = nil,
        chatSendRequest: PingviChatSendRequest? = nil,
        chatSendResult: PingviChatSendResult? = nil,
        createChatRequest: PingviCreateChatRequest? = nil,
        createChatResult: PingviCreateChatResult? = nil
    ) {
        self.version = version
        self.id = id
        self.kind = kind
        self.snapshot = snapshot
        self.reply = reply
        self.replyResult = replyResult
        self.conversationRequest = conversationRequest
        self.conversationResponse = conversationResponse
        self.chatSendRequest = chatSendRequest
        self.chatSendResult = chatSendResult
        self.createChatRequest = createChatRequest
        self.createChatResult = createChatResult
    }

    public static func snapshot(_ value: PingviSnapshot) -> Self {
        Self(kind: .snapshot, snapshot: value)
    }

    public static func reply(_ value: PingviReply, id: String = UUID().uuidString) -> Self {
        Self(id: id, kind: .reply, reply: value)
    }

    public static func result(_ value: PingviReplyResult) -> Self {
        Self(kind: .replyResult, replyResult: value)
    }

    public static func requestConversation(_ sessionID: String, id: String = UUID().uuidString) -> Self {
        Self(id: id, kind: .requestConversation, conversationRequest: PingviConversationRequest(sessionID: sessionID))
    }

    public static func conversation(_ value: PingviConversationResponse) -> Self {
        Self(kind: .conversation, conversationResponse: value)
    }

    public static func chatSend(_ value: PingviChatSendRequest, id: String = UUID().uuidString) -> Self {
        Self(id: id, kind: .chatSend, chatSendRequest: value)
    }

    public static func chatSendResult(_ value: PingviChatSendResult) -> Self {
        Self(kind: .chatSendResult, chatSendResult: value)
    }

    public static func createChat(_ value: PingviCreateChatRequest, id: String = UUID().uuidString) -> Self {
        Self(id: id, kind: .createChat, createChatRequest: value)
    }

    public static func createChatResult(_ value: PingviCreateChatResult) -> Self {
        Self(kind: .createChatResult, createChatResult: value)
    }
}

public enum PingviLinkError: LocalizedError, Equatable {
    case invalidPairingOffer
    case pairingExpired
    case authenticationFailed
    case incompatibleVersion(Int)
    case invalidMessage
    case frameTooLarge(Int)
    case replayedFrame
    case disconnected

    public var errorDescription: String? {
        switch self {
        case .invalidPairingOffer: return "Код сопряжения недействителен."
        case .pairingExpired: return "Код сопряжения истёк. Создайте новый на Mac."
        case .authenticationFailed: return "Не удалось подтвердить доверенное устройство."
        case .incompatibleVersion(let version): return "Версия протокола \(version) не поддерживается."
        case .invalidMessage: return "Получено повреждённое сообщение."
        case .frameTooLarge: return "Сообщение превышает допустимый размер."
        case .replayedFrame: return "Повторное сетевое сообщение отклонено."
        case .disconnected: return "Соединение с устройством прервано."
        }
    }
}
