import PingviLink
import SwiftUI
import UIKit

struct MobileRootView: View {
    @EnvironmentObject private var model: MobileAppModel

    var body: some View {
        Group {
            #if DEBUG
            if MobileDocumentationPreview.isEnabled,
               MobileDocumentationPreview.screen == .conversation,
               let session = model.sessions.first(where: { $0.id == MobileDocumentationPreview.conversationSessionID }) {
                NavigationStack { ConversationView(session: session) }
            } else if model.isPaired { PairedRootView() }
            else { PairingView() }
            #else
            if model.isPaired { PairedRootView() }
            else { PairingView() }
            #endif
        }
        .alert("Pingvi", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

private struct PairedRootView: View {
    @State private var selection: Int

    init() {
        #if DEBUG
        _selection = State(initialValue: MobileDocumentationPreview.isEnabled ? MobileDocumentationPreview.initialTab : 0)
        #else
        _selection = State(initialValue: 0)
        #endif
    }

    var body: some View {
        TabView(selection: $selection) {
            QueueView()
                .tabItem { Label("Очередь", systemImage: "tray.full") }
                .tag(0)
            DialogsView()
                .tabItem { Label("Диалоги", systemImage: "bubble.left.and.bubble.right") }
                .tag(1)
            NavigationStack { MobileSettingsView() }
                .tabItem { Label("Настройки", systemImage: "gearshape") }
                .tag(2)
        }
    }
}

private struct BrandMark: View {
    var size: CGFloat = 76

    var body: some View {
        Image("IconIce")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
            .shadow(color: MobilePalette.accent.opacity(0.24), radius: 20, y: 8)
            .accessibilityHidden(true)
    }
}

struct PairingView: View {
    @EnvironmentObject private var model: MobileAppModel
    @State private var scanning = false
    @State private var code = ""

    var body: some View {
        NavigationStack {
            ZStack {
                MobileAmbientBackground()
                ScrollView {
                    VStack(spacing: 28) {
                        BrandMark(size: 92)
                        VStack(spacing: 10) {
                            Text("Подключите Pingvi к Mac")
                                .font(.largeTitle.bold())
                                .multilineTextAlignment(.center)
                            Text("Вопросы агентов — на iPhone и Apple Watch. Ответы возвращаются на Mac напрямую через локальную сеть.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        VStack(alignment: .leading, spacing: 18) {
                            Label("На Mac откройте Настройки → Подключения → Подключить iPhone", systemImage: "macbook")
                                .font(.headline)
                            Label("Оставьте устройства в одной локальной сети", systemImage: "wifi")
                                .foregroundStyle(.secondary)
                            Button {
                                scanning = true
                            } label: {
                                Label("Сканировать QR-код", systemImage: "qrcode.viewfinder")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .mobilePrimaryButton()

                            DisclosureGroup("Ввести код вручную") {
                                VStack(spacing: 12) {
                                    TextField("pingvi://pair…", text: $code, axis: .vertical)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .textFieldStyle(.roundedBorder)
                                    Button("Подключить") { model.pair(qrValue: code) }
                                        .disabled(!code.hasPrefix("pingvi://"))
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                .padding(.top, 10)
                            }
                        }
                        .padding(22)
                        .mobileGlassCard()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 36)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Pingvi")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $scanning) {
                NavigationStack {
                    QRScanner { value in
                        scanning = false
                        model.pair(qrValue: value)
                    }
                    .ignoresSafeArea()
                    .navigationTitle("QR-код на Mac")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("Отмена") { scanning = false } }
                }
            }
        }
    }
}

struct QueueView: View {
    @EnvironmentObject private var model: MobileAppModel

    var body: some View {
        NavigationStack {
            ZStack {
                MobileAmbientBackground()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        connectionHeader

                        if model.questions.isEmpty {
                            ContentUnavailableView(
                                "Никто не ждёт",
                                systemImage: "checkmark.circle",
                                description: Text("Новые вопросы появятся здесь при активном соединении с Mac.")
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 34)
                            .mobileGlassCard()
                        } else {
                            sectionTitle("Ждут ответа", count: model.questions.count)
                            ForEach(model.questions) { question in
                                NavigationLink {
                                    QuestionView(question: question)
                                } label: {
                                    QuestionCard(question: question)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if !model.snapshot.completions.isEmpty {
                            sectionTitle("Готовые результаты", count: model.snapshot.completions.count)
                                .padding(.top, 6)
                            ForEach(model.snapshot.completions) { item in
                                if let session = model.snapshot.sessions.first(where: { $0.id == item.id }) {
                                    NavigationLink {
                                        ConversationView(session: session)
                                    } label: {
                                        HStack(spacing: 14) {
                                            Image(systemName: "checkmark.bubble.fill")
                                                .font(.title2)
                                                .foregroundStyle(.green)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(item.title).font(.headline)
                                                Text("Открыть готовый результат")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption.bold())
                                                .foregroundStyle(.tertiary)
                                        }
                                        .padding(18)
                                        .mobileGlassCard(radius: 20)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { model.activate() }
            }
            .navigationTitle("Pingvi")
        }
    }

    private var connectionHeader: some View {
        HStack(spacing: 14) {
            BrandMark(size: 58)
            VStack(alignment: .leading, spacing: 5) {
                Text("Очередь агента").font(.title2.bold())
                Label(model.state.description,
                      systemImage: model.state == .connected ? "checkmark.circle.fill" : "wifi.slash")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(model.state == .connected ? .green : .secondary)
            }
            Spacer()
        }
        .padding(18)
        .mobileGlassCard()
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).font(.title3.bold())
            Text("\(count)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

struct DialogsView: View {
    @EnvironmentObject private var model: MobileAppModel
    @State private var search = ""
    @State private var showNewChat = false

    private var filtered: [PingviSessionSummary] {
        guard !search.isEmpty else { return model.sessions }
        return model.sessions.filter {
            ($0.title + " " + $0.project + " " + $0.agent + " " + $0.preview)
                .localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MobileAmbientBackground()
                if filtered.isEmpty {
                    ContentUnavailableView(
                        search.isEmpty ? "Диалогов нет" : "Ничего не найдено",
                        systemImage: search.isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass",
                        description: Text(search.isEmpty ? "Сессии с Mac появятся здесь." : "Попробуйте изменить запрос.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filtered) { session in
                                NavigationLink {
                                    ConversationView(session: session)
                                } label: {
                                    SessionCard(session: session)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .frame(maxWidth: 720)
                        .frame(maxWidth: .infinity)
                    }
                    .refreshable { model.activate() }
                }
            }
            .navigationTitle("Диалоги")
            .searchable(text: $search, prompt: "Название, проект или текст")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNewChat = true } label: { Image(systemName: "square.and.pencil") }
                        .disabled(model.state != .connected || model.snapshot.projects.isEmpty)
                        .accessibilityLabel("Новый диалог")
                }
            }
            .sheet(isPresented: $showNewChat) { NewMobileChatView() }
        }
    }
}

private struct SessionCard: View {
    let session: PingviSessionSummary

    private var symbol: String {
        switch session.status {
        case "waiting", "checking", "unconfirmed": return "hand.raised.fill"
        case "working": return "ellipsis.bubble.fill"
        case "done": return "checkmark.bubble.fill"
        case "offline": return "wifi.slash"
        default: return "bubble.left.and.bubble.right.fill"
        }
    }

    private var color: Color {
        switch session.status {
        case "waiting", "checking", "unconfirmed": return .orange
        case "working": return MobilePalette.accent
        case "done": return .green
        case "offline": return .secondary
        default: return MobilePalette.deep
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(session.title).font(.headline).lineLimit(2)
                    if session.status == "done" {
                        Circle().fill(.blue).frame(width: 7, height: 7).accessibilityLabel("Не просмотрено")
                    }
                }
                Text(session.preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 5) {
                    Text(session.agent.capitalized)
                    Text("·")
                    Text(session.project)
                    Spacer()
                    Text(session.updatedAt, style: .relative)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .padding(.top, 5)
        }
        .padding(18)
        .mobileGlassCard(radius: 20, selected: session.status == "done")
        .accessibilityElement(children: .combine)
    }
}

struct ConversationView: View {
    @EnvironmentObject private var model: MobileAppModel
    let session: PingviSessionSummary
    @State private var draft = ""

    private var currentSession: PingviSessionSummary {
        model.snapshot.sessions.first(where: { $0.id == session.id }) ?? session
    }

    private var conversation: PingviConversation? { model.conversations[session.id] }
    private var question: PingviQuestion? { model.snapshot.questions.first(where: { $0.id == session.id }) }
    private var sending: Bool { model.sendingChats.contains(session.id) }

    var body: some View {
        ZStack {
            MobileAmbientBackground()
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        conversationHeader
                        if let question {
                            NavigationLink {
                                QuestionView(question: question)
                            } label: {
                                HStack {
                                    Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                                    Text("Агент ждёт ответа").font(.headline)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .padding(16)
                                .mobileGlassCard(radius: 18, selected: true)
                            }
                            .buttonStyle(.plain)
                        }
                        if model.loadingConversations.contains(session.id) && conversation == nil {
                            ProgressView("Загружаем переписку…")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 36)
                        } else if let conversation {
                            if conversation.partial {
                                Label("Показана доступная часть истории", systemImage: "clock.badge.exclamationmark")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !conversation.context.isEmpty {
                                DisclosureGroup("Недавний контекст") {
                                    Text(conversation.context).font(.callout.monospaced()).textSelection(.enabled)
                                }
                                .padding(16)
                                .mobileGlassCard(radius: 18)
                            }
                            if conversation.messages.isEmpty && conversation.context.isEmpty {
                                ContentUnavailableView("Сообщений пока нет", systemImage: "bubble.left", description: Text("Напишите первое сообщение, когда агент готов."))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 32)
                            }
                            ForEach(conversation.messages) { message in
                                ChatBubble(message: message, agent: conversation.agent)
                            }
                            if conversation.busy {
                                Label("Агент пишет…", systemImage: "ellipsis.bubble")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                composer
            }
        }
        .navigationTitle(currentSession.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.loadConversation(sessionID: session.id, force: true) } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(model.state != .connected || model.loadingConversations.contains(session.id))
                .accessibilityLabel("Обновить переписку")
            }
        }
        .task(id: session.id) { model.loadConversation(sessionID: session.id) }
    }

    private var conversationHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(currentSession.title).font(.title2.bold())
            Text(currentSession.agent.capitalized + " · " + currentSession.project)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(currentSession.preview).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .mobileGlassCard()
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Сообщение агенту…", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Button {
                    let text = draft
                    model.sendChat(sessionID: session.id, text: text)
                    if conversation?.canSend == true && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        draft = ""
                    }
                } label: {
                    Image(systemName: sending ? "ellipsis" : "arrow.up")
                        .font(.headline)
                        .frame(width: 22, height: 22)
                }
                .mobilePrimaryButton()
                .disabled(model.state != .connected || conversation?.canSend != true || sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Отправить")
            }
            Text(conversation?.canSend == true ? "Сообщение будет передано в исходную сессию на Mac." : (conversation?.reason ?? "Проверяем готовность агента…"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }
}

private struct ChatBubble: View {
    let message: PingviChatMessage
    let agent: String

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 5) {
            Text(message.role == .user ? "Вы" : agent.capitalized)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(message.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
            if message.state == .submitted || message.state == .uncertain || message.state == .checked {
                Text(messageState)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(message.role == .user ? 14 : 0)
        .background(message.role == .user ? MobilePalette.accent.opacity(0.14) : .clear,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var messageState: String {
        switch message.state {
        case .submitted: return "Передано в сессию · ожидаем подтверждения"
        case .uncertain: return "Результат отправки неизвестен"
        case .checked: return "Проверено в исходной сессии"
        case .received: return ""
        }
    }
}

struct NewMobileChatView: View {
    @EnvironmentObject private var model: MobileAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var agent = "codex"
    @State private var projectPath = ""
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Агент") {
                    Picker("Агент", selection: $agent) {
                        Text("Codex").tag("codex")
                        Text("Claude Code").tag("claude")
                    }
                    .pickerStyle(.segmented)
                }
                Section("Проект") {
                    Picker("Проект", selection: $projectPath) {
                        Text("Выберите проект").tag("")
                        ForEach(model.snapshot.projects) { project in
                            Text(project.name).tag(project.path)
                        }
                    }
                }
                Section("Первая задача или сообщение") {
                    TextField("Что нужно сделать?", text: $text, axis: .vertical)
                        .lineLimit(5...12)
                }
            }
            .navigationTitle("Новый диалог")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.creatingChat ? "Создаём…" : "Начать") {
                        model.createChat(agent: agent, projectPath: projectPath, text: text)
                    }
                    .disabled(model.creatingChat || projectPath.isEmpty || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { if projectPath.isEmpty { projectPath = model.snapshot.projects.first?.path ?? "" } }
            .onChange(of: model.createdSessionID) { _, id in if id != nil { dismiss() } }
        }
    }
}

private struct QuestionCard: View {
    let question: PingviQuestion

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "bubble.left.and.exclamationmark.bubble.right.fill")
                .font(.title2)
                .foregroundStyle(MobilePalette.accent)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 7) {
                Text(question.title).font(.headline)
                Text(question.question)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                Text(question.agent + " · " + question.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .padding(.top, 5)
        }
        .padding(18)
        .mobileGlassCard(radius: 20)
        .accessibilityElement(children: .combine)
    }
}

struct QuestionView: View {
    @EnvironmentObject private var model: MobileAppModel
    let question: PingviQuestion
    @State private var answer = ""
    @State private var fieldAnswers: [String: String] = [:]

    var current: PingviQuestion? {
        model.snapshot.questions.first { $0.id == question.id && $0.token == question.token }
    }

    var body: some View {
        Form {
            Section {
                Text(question.question).font(.body)
                if !question.context.isEmpty {
                    DisclosureGroup("Контекст") { Text(question.context).textSelection(.enabled) }
                }
            } header: {
                Text(question.agent + " · " + question.source)
            }
            if !question.options.isEmpty {
                Section("Быстрый ответ") {
                    ForEach(question.options) { option in
                        Button {
                            submit(answer: option.replyValue)
                        } label: {
                            HStack {
                                Text(option.label)
                                Spacer()
                                Image(systemName: "arrow.up.circle.fill")
                            }
                        }
                        .disabled(!canSubmit)
                    }
                }
            }
            ForEach(question.fields) { field in
                Section(field.label) {
                    Picker("Ответ", selection: Binding(
                        get: { fieldAnswers[field.id] ?? "" },
                        set: { fieldAnswers[field.id] = $0 }
                    )) {
                        Text("Не выбрано").tag("")
                        ForEach(field.options) { option in Text(option.label).tag(option.label) }
                    }
                }
            }
            Section("Короткий ответ") {
                TextField("Продиктуйте или введите ответ", text: $answer, axis: .vertical)
                    .lineLimit(2...6)
                Button(model.replyingSessions.contains(question.id) ? "Отправляем…" : "Отправить") { submit(answer: answer) }
                    .disabled(!canSubmit || (answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && fieldAnswers.values.allSatisfy(\.isEmpty)))
            }
            if current == nil {
                Text("Вопрос уже закрыт или изменился.").foregroundStyle(.secondary)
            } else if current?.state != .waiting {
                Text(current?.state == .checking ? "Ответ отправлен · проверяем" : "Результат отправки неизвестен")
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background { MobileAmbientBackground() }
        .navigationTitle(question.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var canSubmit: Bool {
        model.state == .connected && current?.canReply == true && !model.replyingSessions.contains(question.id)
    }

    private func submit(answer value: String) {
        _ = model.send(PingviReply(
            sessionID: question.id,
            questionToken: question.token,
            answer: value.trimmingCharacters(in: .whitespacesAndNewlines),
            fieldAnswers: fieldAnswers.filter { !$0.value.isEmpty }
        ))
    }
}

struct MobileSettingsView: View {
    @EnvironmentObject private var model: MobileAppModel
    @EnvironmentObject private var appearance: MobileAppearance
    @AppStorage("appTheme") private var theme = MobileTheme.system.rawValue
    @AppStorage("fullNotificationPreviews") private var fullPreviews = false
    @State private var confirmForget = false

    var body: some View {
        Form {
            Section("Тема интерфейса") {
                Picker("Тема", selection: $theme) {
                    ForEach(MobileTheme.allCases) { item in
                        Text(item.title).tag(item.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text("«Как в iOS» следует системному оформлению устройства.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Иконка") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 14) {
                    ForEach(MobileIconMood.allCases) { mood in
                        Button { appearance.select(mood) } label: {
                            VStack(spacing: 8) {
                                Image(mood.previewName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 66, height: 66)
                                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                                    .shadow(color: .black.opacity(0.12), radius: 5, y: 3)
                                HStack(spacing: 4) {
                                    Text(mood.title).font(.caption.weight(.semibold))
                                    if appearance.selectedIcon == mood {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(MobilePalette.accent)
                                    }
                                }
                                Text(mood.caption)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(height: 30)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(10)
                            .mobileGlassCard(radius: 18, selected: appearance.selectedIcon == mood)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(mood.title)
                        .accessibilityAddTraits(appearance.selectedIcon == mood ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
                Text("iOS попросит подтвердить смену иконки. Выбор сохраняется после перезапуска.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Подключение") {
                LabeledContent("Mac", value: model.pairing?.peerName ?? "Не подключён")
                LabeledContent("Состояние", value: model.state.description)
                if let fingerprint = model.pairing?.fingerprint {
                    LabeledContent("Отпечаток", value: fingerprint)
                }
                Button("Забыть Mac…", role: .destructive) { confirmForget = true }
            }
            Section("Уведомления") {
                Toggle("Показывать текст вопроса", isOn: $fullPreviews)
                Text("По умолчанию на заблокированном экране показывается только факт нового вопроса.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Диагностика") {
                Button("Скопировать диагностику") { UIPasteboard.general.string = model.diagnostics() }
                Text("Тексты вопросов, ответы и ключи не включаются.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("Без Apple Developer Program приложение нужно переустанавливать через Xcode каждые 7 дней. Фоновая доставка в локальной сети не гарантируется.")
                    .font(.caption)
            }
        }
        .scrollContentBackground(.hidden)
        .background { MobileAmbientBackground() }
        .navigationTitle("Настройки")
        .alert("Забыть Mac?", isPresented: $confirmForget) {
            Button("Забыть", role: .destructive) { model.forgetMac() }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Для повторного подключения потребуется новый QR-код.") }
        .alert("Иконка", isPresented: Binding(
            get: { appearance.errorMessage != nil },
            set: { if !$0 { appearance.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { appearance.errorMessage = nil }
        } message: {
            Text(appearance.errorMessage ?? "")
        }
    }
}
