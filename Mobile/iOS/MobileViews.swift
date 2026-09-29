import PingviLink
import SwiftUI
import UIKit

struct MobileRootView: View {
    @EnvironmentObject private var model: MobileAppModel

    var body: some View {
        Group {
            if model.isPaired { PairedRootView() }
            else { PairingView() }
        }
        .mobileToastOverlay()
        .alert("Pingvi", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

private struct MobileTabKey: EnvironmentKey {
    static let defaultValue: MobileTab = .queue
}

extension EnvironmentValues {
    /// The tab whose navigation stack hosts the current view, so nested screens push onto the right path.
    var mobileTab: MobileTab {
        get { self[MobileTabKey.self] }
        set { self[MobileTabKey.self] = newValue }
    }
}

private struct PairedRootView: View {
    @EnvironmentObject private var model: MobileAppModel
    @EnvironmentObject private var router: MobileRouter

    var body: some View {
        TabView(selection: $router.tab) {
            QueueView()
                .tabItem { Label("Очередь", systemImage: "tray.full") }
                .badge(model.questions.count)
                .tag(MobileTab.queue)
            DialogsView()
                .tabItem { Label("Диалоги", systemImage: "bubble.left.and.bubble.right") }
                .badge(model.unreadResultCount)
                .tag(MobileTab.dialogs)
            NavigationStack(path: $router.settingsPath) { MobileSettingsView() }
                .tabItem { Label("Настройки", systemImage: "gearshape") }
                .tag(MobileTab.settings)
        }
        .sheet(item: $router.presentedQuestion) { question in
            NavigationStack { QuestionView(question: question) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct MobileDestinationView: View {
    let destination: MobileDestination

    var body: some View {
        switch destination {
        case .conversation(let session): ConversationView(session: session)
        }
    }
}

private extension View {
    /// Keeps the glass card look inside a plain `List` row while enabling native list behaviour.
    func mobileListRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    func mobileListStyle() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background { MobileAmbientBackground() }
    }
}

private struct MobileSectionHeader: View {
    let title: LocalizedStringKey
    var count: Int?
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            if let count {
                Text("\(count)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
            }
        }
        .textCase(nil)
        .padding(.horizontal, 4)
        .padding(.top, 8)
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
                                .accessibilityAddTraits(.isHeader)
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
                                    HStack {
                                        PasteButton(payloadType: String.self) { values in
                                            if let value = values.first { code = value }
                                        }
                                        .buttonBorderShape(.capsule)
                                        .labelStyle(.titleAndIcon)
                                        Spacer()
                                        Button("Подключить") { model.pair(qrValue: code) }
                                            .buttonStyle(.bordered)
                                            .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.pairingInProgress)
                                    }
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
            .toolbar(.hidden, for: .navigationBar)
            .overlay {
                if model.pairingInProgress {
                    ZStack {
                        Color.black.opacity(0.15).ignoresSafeArea()
                        VStack(spacing: 14) {
                            ProgressView().controlSize(.large)
                            Text("Подключаемся к Mac…").font(.headline)
                            Text("Держите устройства в одной сети.").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(28)
                        .mobileGlassCard(radius: 24)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .sheet(isPresented: $scanning) {
                NavigationStack {
                    QRScannerScreen { value in
                        scanning = false
                        model.pair(qrValue: value)
                    }
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
    @EnvironmentObject private var router: MobileRouter

    var body: some View {
        NavigationStack(path: $router.queuePath) {
            List {
                QueueConnectionHeader()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 4, trailing: 16))
                Section {
                    if model.questions.isEmpty {
                        ContentUnavailableView(
                            "Никто не ждёт",
                            systemImage: "checkmark.circle",
                            description: Text("Новые вопросы агентов появятся здесь.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .mobileGlassCard()
                        .mobileListRow()
                    } else {
                        ForEach(model.questions) { question in
                            QuestionRow(question: question)
                                .mobileListRow()
                        }
                    }
                } header: {
                    if model.questions.isEmpty {
                        EmptyView()
                    } else {
                        MobileSectionHeader(title: "Ждут ответа", count: model.questions.count)
                    }
                }
                .listSectionSeparator(.hidden)

                if !model.snapshot.completions.isEmpty {
                    Section {
                        ForEach(model.snapshot.completions) { item in
                            if let session = model.snapshot.sessions.first(where: { $0.id == item.id }) {
                                Button { router.push(.conversation(session), in: .queue) } label: {
                                    CompletionCard(completion: item, marking: model.markingReadSessions.contains(item.id))
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button { model.markConversationRead(sessionID: item.id) } label: {
                                        Label("Прочитано", systemImage: "checkmark")
                                    }
                                    .tint(.green)
                                }
                                .contextMenu {
                                    Button { model.markConversationRead(sessionID: item.id) } label: {
                                        Label("Отметить прочитанным", systemImage: "checkmark")
                                    }
                                    Button { router.push(.conversation(session), in: .queue) } label: {
                                        Label("Открыть диалог", systemImage: "bubble.left.and.bubble.right")
                                    }
                                }
                                .mobileListRow()
                            }
                        }
                    } header: {
                        MobileSectionHeader(
                            title: "Готовые результаты",
                            count: model.snapshot.completions.count,
                            actionTitle: model.snapshot.completions.count > 1 && model.state == .connected ? "Прочитать все" : nil,
                            action: { model.markAllResultsRead() }
                        )
                    }
                    .listSectionSeparator(.hidden)
                }
            }
            .mobileListStyle()
            .refreshable { model.activate() }
            .navigationTitle("Очередь")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MobileDestination.self) { MobileDestinationView(destination: $0) }
        }
        .environment(\.mobileTab, .queue)
    }
}

/// Top of the queue: the paired Mac as the screen's anchor, with live connection status.
/// Replaces the generic connection banner on this tab so the status is shown once.
private struct QueueConnectionHeader: View {
    @EnvironmentObject private var model: MobileAppModel

    private var inProgress: Bool { model.state == .searching || model.state == .connecting }
    private var connected: Bool { model.state == .connected }

    private var statusText: String {
        switch model.state {
        case .connected: return String(localized: "На связи")
        case .searching, .connecting: return model.state.description
        default: return String(localized: "Нет связи")
        }
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.pairing?.peerName ?? "Mac")
                        .font(.largeTitle.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if inProgress {
                            ProgressView().controlSize(.mini)
                        } else {
                            Circle()
                                .fill(connected ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        }
                        Text(subtitle(now: context.date))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if !connected && !inProgress {
                    Button("Повторить") { model.reconnect() }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.bordered)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func subtitle(now: Date) -> String {
        // While connected the data is live, so the sync time only matters when it may be stale.
        guard !connected, let updated = MobileSyncText.updated(model.lastSyncAt, now: now) else { return statusText }
        return statusText + " · " + updated
    }
}

private struct CompletionCard: View {
    let completion: PingviCompletion
    var marking = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: marking ? "ellipsis.bubble.fill" : "checkmark.bubble.fill")
                .font(.title2)
                .foregroundStyle(.green)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 6) {
                Text(completion.title).font(.headline)
                Text(completion.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                HStack(spacing: 5) {
                    Text(completion.agent.capitalized)
                    Text("·")
                    Text(completion.completedAt, style: .relative)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .padding(.top, 5)
        }
        .padding(18)
        .mobileGlassCard(radius: 20)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct ReplyFailureRow: View {
    @EnvironmentObject private var model: MobileAppModel
    let sessionID: String
    let failure: MobileReplyFailure

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Не доставлено").font(.subheadline.weight(.semibold))
                if !failure.message.isEmpty {
                    Text(failure.message).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button("Повторить") { model.retryReply(sessionID: sessionID) }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
                .disabled(model.state != .connected || model.replyingSessions.contains(sessionID))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

/// Same status filters as the Mac dashboard (`SessionFilter` in the Mac app).
enum DialogsFilter: String, CaseIterable, Identifiable {
    case all
    case waiting
    case working
    case done

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .all: return "Все"
        case .waiting: return "Ждут"
        case .working: return "В работе"
        case .done: return "Готово"
        }
    }

    func includes(_ session: PingviSessionSummary) -> Bool {
        let status = session.sessionStatus
        switch self {
        case .all: return true
        case .waiting: return status.awaitsAnswer
        case .working: return status == .working
        case .done: return status.isUnreadResult
        }
    }
}

enum DialogsGrouping {
    struct Group: Identifiable, Equatable {
        let id: String
        let title: String
        let sessions: [PingviSessionSummary]
    }

    /// Sections for the "Все" filter: what needs an answer, what is running, then everything else.
    static func groups(_ sessions: [PingviSessionSummary]) -> [Group] {
        let waiting = sessions.filter { $0.sessionStatus.awaitsAnswer }
        let working = sessions.filter { $0.sessionStatus == .working }
        let rest = sessions.filter { !$0.sessionStatus.awaitsAnswer && $0.sessionStatus != .working }
        return [
            Group(id: "waiting", title: String(localized: "Ждут ответа"), sessions: waiting),
            Group(id: "working", title: String(localized: "В работе"), sessions: working),
            Group(id: "recent", title: String(localized: "Недавние"), sessions: rest)
        ].filter { !$0.sessions.isEmpty }
    }
}

struct DialogsView: View {
    @EnvironmentObject private var model: MobileAppModel
    @EnvironmentObject private var router: MobileRouter
    @AppStorage("dialogsFilter") private var filterRaw = DialogsFilter.all.rawValue
    @AppStorage("dialogsProject") private var project = ""
    @State private var search = ""
    @State private var showNewChat = false

    private var filter: DialogsFilter { DialogsFilter(rawValue: filterRaw) ?? .all }

    private var projects: [String] {
        Array(Set(model.sessions.map(\.project).filter { !$0.isEmpty })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var filtered: [PingviSessionSummary] {
        model.sessions.filter { session in
            filter.includes(session)
                && (project.isEmpty || session.project == project)
                && (search.isEmpty || (session.title + " " + session.project + " " + session.agent + " " + session.preview)
                    .localizedCaseInsensitiveContains(search))
        }
    }

    private var newChatUnavailableReason: String? {
        if model.state != .connected { return String(localized: "Новый диалог можно начать, когда есть связь с Mac.") }
        if model.snapshot.projects.isEmpty { return String(localized: "На Mac пока нет проектов. Запустите Claude Code или Codex в папке проекта.") }
        return nil
    }

    var body: some View {
        NavigationStack(path: $router.dialogsPath) {
            List {
                Section {
                    filterChips
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                }
                if filtered.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: search.isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass",
                        description: Text(emptyDescription)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .mobileListRow()
                } else if filter == .all && search.isEmpty {
                    ForEach(DialogsGrouping.groups(filtered)) { group in
                        Section {
                            ForEach(group.sessions) { sessionRow($0) }
                        } header: {
                            MobileSectionHeader(title: LocalizedStringKey(group.title), count: group.sessions.count)
                        }
                        .listSectionSeparator(.hidden)
                    }
                } else {
                    Section {
                        ForEach(filtered) { sessionRow($0) }
                    }
                    .listSectionSeparator(.hidden)
                }
            }
            .mobileListStyle()
            .refreshable { model.activate() }
            .mobileConnectionBanner()
            .navigationTitle("Диалоги")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Название, проект или текст")
            .toolbar {
                // The tab bar already names the screen; keep the title only for the back button.
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let reason = newChatUnavailableReason { model.showToast(reason) }
                        else { showNewChat = true }
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(newChatUnavailableReason == nil ? MobilePalette.accent : .secondary)
                    }
                    .accessibilityLabel("Новый диалог")
                    .accessibilityHint(newChatUnavailableReason ?? "")
                }
            }
            .sheet(isPresented: $showNewChat) { NewMobileChatView() }
            .onChange(of: model.createdSession) { _, session in
                guard let session else { return }
                model.createdSession = nil
                router.push(.conversation(session), in: .dialogs)
            }
            .onChange(of: projects) { _, available in
                if !project.isEmpty && !available.contains(project) { project = "" }
            }
            .navigationDestination(for: MobileDestination.self) { MobileDestinationView(destination: $0) }
        }
        .environment(\.mobileTab, .dialogs)
    }

    private var emptyTitle: LocalizedStringKey {
        if !search.isEmpty { return "Ничего не найдено" }
        if filter == .waiting { return "Никто не ждёт" }
        if filter == .working { return "Сейчас никто не работает" }
        if filter == .done { return "Новых результатов нет" }
        return project.isEmpty ? "Диалогов нет" : "В проекте нет диалогов"
    }

    private var emptyDescription: LocalizedStringKey {
        if !search.isEmpty || filter != .all || !project.isEmpty { return "Попробуйте изменить фильтр или запрос." }
        return "Сессии с Mac появятся здесь."
    }

    private var filterChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(DialogsFilter.allCases) { item in
                    chip(item.title, selected: filter == item) {
                        MobileHaptics.selection()
                        filterRaw = item.rawValue
                    }
                }
                if projects.count > 1 || !project.isEmpty {
                    Menu {
                        Button { project = "" } label: {
                            if project.isEmpty { Label("Все проекты", systemImage: "checkmark") } else { Text("Все проекты") }
                        }
                        ForEach(projects, id: \.self) { name in
                            Button { project = name } label: {
                                if project == name { Label(name, systemImage: "checkmark") } else { Text(name) }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(project.isEmpty ? String(localized: "Проект") : project).lineLimit(1)
                            Image(systemName: "chevron.down").font(.caption2.bold())
                        }
                        .chipStyle(selected: !project.isEmpty)
                    }
                    .accessibilityLabel(project.isEmpty ? "Фильтр по проекту" : "Проект: \(project)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ title: LocalizedStringKey, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).chipStyle(selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func sessionRow(_ session: PingviSessionSummary) -> some View {
        let question = model.snapshot.questions.first { $0.id == session.id }
        return Button { router.push(.conversation(session), in: .dialogs) } label: {
            SessionCard(session: session, marking: model.markingReadSessions.contains(session.id))
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if session.sessionStatus.isUnreadResult {
                Button { model.markConversationRead(sessionID: session.id) } label: {
                    Label("Прочитано", systemImage: "checkmark")
                }
                .tint(.green)
            }
        }
        .contextMenu {
            if session.sessionStatus.isUnreadResult {
                Button { model.markConversationRead(sessionID: session.id) } label: {
                    Label("Отметить прочитанным", systemImage: "checkmark")
                }
            }
            if let question {
                Button { router.present(question) } label: {
                    Label("Открыть вопрос", systemImage: "hand.raised")
                }
            }
            Button {
                UIPasteboard.general.string = session.title
                model.showToast(String(localized: "Название скопировано"), style: .success)
            } label: {
                Label("Скопировать название", systemImage: "doc.on.doc")
            }
        }
        .mobileListRow()
    }
}

private extension View {
    func chipStyle(selected: Bool) -> some View {
        font(.subheadline.weight(.semibold))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(selected ? AnyShapeStyle(MobilePalette.accent) : AnyShapeStyle(.thinMaterial), in: Capsule())
            .contentShape(Capsule())
    }
}

private struct SessionCard: View {
    let session: PingviSessionSummary
    var marking = false

    var body: some View {
        let status = session.sessionStatus
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: marking ? "ellipsis.bubble.fill" : status.symbol)
                .font(.title2)
                .foregroundStyle(status.color)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(session.title).font(.headline).lineLimit(2)
                    if status.isUnreadResult {
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
        .mobileGlassCard(radius: 20, selected: status.isUnreadResult)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct ConversationView: View {
    @EnvironmentObject private var model: MobileAppModel
    @EnvironmentObject private var router: MobileRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: PingviSessionSummary
    @State private var draft = ""
    @State private var positionedAtLatestMessage = false
    @State private var atBottom = true
    @State private var hasUnseenMessages = false

    private let bottomAnchorID = "conversation-bottom"

    private var currentSession: PingviSessionSummary {
        model.snapshot.sessions.first(where: { $0.id == session.id }) ?? session
    }

    private var conversation: PingviConversation? { model.conversations[session.id] }
    private var question: PingviQuestion? { model.snapshot.questions.first(where: { $0.id == session.id }) }
    private var sending: Bool { model.sendingChats.contains(session.id) }
    private var busy: Bool { conversation?.busy == true }

    var body: some View {
        ZStack {
            MobileAmbientBackground()
            VStack(spacing: 0) {
                if let question { pinnedQuestion(question) }
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            messages
                            Color.clear.frame(height: 1).id(bottomAnchorID)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .frame(maxWidth: 720)
                        .frame(maxWidth: .infinity)
                    }
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 80
                    } action: { _, nearBottom in
                        atBottom = nearBottom
                        if nearBottom { hasUnseenMessages = false }
                    }
                    .onChange(of: conversation?.messages.map(\.id) ?? [], initial: true) { old, messageIDs in
                        if !positionedAtLatestMessage {
                            positionAtLatestMessageIfNeeded(reader, messageIDs: messageIDs)
                        } else if messageIDs != old {
                            followNewContent(reader)
                        }
                    }
                    .onChange(of: busy) { _, _ in if positionedAtLatestMessage { followNewContent(reader) } }
                    .onChange(of: model.chatFailures[session.id] != nil) { _, _ in followNewContent(reader) }
                    .overlay(alignment: .bottom) {
                        if hasUnseenMessages {
                            Button {
                                scrollToBottom(reader)
                                hasUnseenMessages = false
                            } label: {
                                Label("Новые сообщения", systemImage: "arrow.down")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                            }
                            .buttonStyle(.plain)
                            .mobileGlassCard(radius: 20, selected: true)
                            .padding(.bottom, 10)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(reduceMotion ? nil : .snappy, value: hasUnseenMessages)
                }
                composer
            }
        }
        .mobileConnectionBanner()
        .navigationTitle(currentSession.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(currentSession.title).font(.headline).lineLimit(1)
                    Text(currentSession.agent.capitalized + " · " + currentSession.project)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            if currentSession.sessionStatus.isUnreadResult {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.markConversationRead(sessionID: session.id) } label: {
                        Image(systemName: "checkmark.circle")
                    }
                    .disabled(model.state != .connected || model.markingReadSessions.contains(session.id))
                    .accessibilityLabel("Отметить диалог прочитанным")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.loadConversation(sessionID: session.id, force: true) } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(model.state != .connected || model.loadingConversations.contains(session.id))
                .accessibilityLabel("Обновить переписку")
            }
        }
        .task(id: session.id) {
            draft = model.chatDraft(for: session.id)
            model.loadConversation(sessionID: session.id)
        }
        .task(id: busy) { await pollWhileBusy() }
        .onChange(of: draft) { _, text in model.setChatDraft(text, for: session.id) }
        .onChange(of: model.state == .connected) { _, connected in
            if connected && conversation == nil { model.loadConversation(sessionID: session.id) }
        }
    }

    @ViewBuilder
    private var messages: some View {
        if let error = model.conversationErrors[session.id] {
            inlineNotice(error, systemImage: "exclamationmark.triangle.fill")
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
                TypingIndicator(agent: conversation.agent)
            }
        }
        if let failure = model.chatFailures[session.id] {
            FailedChatBubble(sessionID: session.id, failure: failure)
        }
    }

    private func pinnedQuestion(_ question: PingviQuestion) -> some View {
        Button { router.present(question) } label: {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Агент ждёт ответа").font(.subheadline.weight(.semibold))
                    Text(question.question).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text("Ответить").font(.subheadline.weight(.semibold)).foregroundStyle(MobilePalette.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .mobileGlassCard(radius: 18, selected: true)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }

    /// Reloads the conversation while the agent is writing so new text appears without manual refresh.
    private func pollWhileBusy() async {
        guard busy else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, model.conversations[session.id]?.busy == true else { return }
            if model.state == .connected && !model.loadingConversations.contains(session.id) {
                model.loadConversation(sessionID: session.id, force: true)
            }
        }
    }

    private func positionAtLatestMessageIfNeeded(_ reader: ScrollViewProxy, messageIDs: [String]) {
        guard !positionedAtLatestMessage, !messageIDs.isEmpty else { return }
        positionedAtLatestMessage = true
        Task { @MainActor in
            await Task.yield()
            reader.scrollTo(bottomAnchorID, anchor: .bottom)
        }
    }

    /// Keeps the reader at the latest message only if they were already there.
    private func followNewContent(_ reader: ScrollViewProxy) {
        if atBottom {
            Task { @MainActor in
                await Task.yield()
                scrollToBottom(reader)
            }
        } else {
            hasUnseenMessages = true
        }
    }

    private func scrollToBottom(_ reader: ScrollViewProxy) {
        if reduceMotion {
            reader.scrollTo(bottomAnchorID, anchor: .bottom)
        } else {
            withAnimation(.snappy) { reader.scrollTo(bottomAnchorID, anchor: .bottom) }
        }
    }

    private func inlineNotice(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .mobileGlassCard(radius: 18)
    }

    private var composerNotice: String? {
        guard let conversation, !conversation.canSend else { return nil }
        return conversation.reason.isEmpty ? String(localized: "Агент сейчас не принимает сообщения.") : conversation.reason
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
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
            if let composerNotice {
                Label(composerNotice, systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }
}

private struct TypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let agent: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(agent.capitalized)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TimelineView(.periodic(from: .now, by: 0.4)) { context in
                let phase = reduceMotion ? -1 : Int(context.date.timeIntervalSinceReferenceDate / 0.4) % 3
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(.secondary)
                            .frame(width: 7, height: 7)
                            .opacity(phase == index ? 1 : 0.35)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.thinMaterial, in: Capsule())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Агент пишет…")
    }
}

private struct ChatBubble: View {
    let message: PingviChatMessage
    let agent: String

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 5) {
            Text(message.role == .user ? String(localized: "Вы") : agent.capitalized)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            if message.role == .user {
                Text(message.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                MobileMarkdownView(message.text)
            }
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
        case .submitted: return String(localized: "Передано в сессию · ожидаем подтверждения")
        case .uncertain: return String(localized: "Результат отправки неизвестен")
        case .checked: return String(localized: "Проверено в исходной сессии")
        case .received: return ""
        }
    }
}

/// A message that never reached the Mac, kept in place so the user can retry without retyping.
private struct FailedChatBubble: View {
    @EnvironmentObject private var model: MobileAppModel
    let sessionID: String
    let failure: MobileChatFailure

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(failure.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(14)
                .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            HStack(spacing: 12) {
                Label(failure.message.isEmpty ? String(localized: "Не отправлено") : failure.message,
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("Повторить") { model.retryChat(sessionID: sessionID) }
                    .font(.caption.weight(.semibold))
                    .disabled(model.state != .connected || model.sendingChats.contains(sessionID) || failure.text.isEmpty)
                Button("Убрать", role: .destructive) { model.discardChatFailure(sessionID: sessionID) }
                    .font(.caption.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct NewMobileChatView: View {
    @EnvironmentObject private var model: MobileAppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("newChatAgent") private var agent = "codex"
    @AppStorage("newChatProject") private var lastProject = ""
    @State private var projectPath = ""
    @State private var text = ""
    @FocusState private var textFocused: Bool

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
                Section {
                    TextField("Что нужно сделать?", text: $text, axis: .vertical)
                        .lineLimit(5...12)
                        .focused($textFocused)
                } header: {
                    Text("Первая задача или сообщение")
                } footer: {
                    if let error = model.createChatError {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Новый диалог")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.creatingChat ? "Создаём…" : "Начать") {
                        lastProject = projectPath
                        model.createChat(agent: agent, projectPath: projectPath, text: text)
                    }
                    .disabled(model.creatingChat || projectPath.isEmpty || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                model.createChatError = nil
                let paths = model.snapshot.projects.map(\.path)
                if projectPath.isEmpty {
                    projectPath = paths.contains(lastProject) ? lastProject : (paths.first ?? "")
                }
                textFocused = true
            }
            .onChange(of: model.createdSessionID) { _, id in if id != nil { dismiss() } }
        }
    }
}

/// Queue row: the question summary opens the answer sheet, plain choices can be answered in place.
private struct QuestionRow: View {
    @EnvironmentObject private var model: MobileAppModel
    @EnvironmentObject private var router: MobileRouter
    @EnvironmentObject private var undo: MobileUndoQueue
    let question: PingviQuestion

    private var sent: Bool {
        model.replyingSessions.contains(question.id) || question.state == .checking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { router.present(question) } label: { summary }
                .buttonStyle(.plain)
            if let pending = undo.pending[question.id] {
                UndoReplyBar(pending: pending) { undo.cancel(sessionID: question.id) }
            } else if sent {
                Label {
                    Text("Отправлено · проверяем")
                } icon: {
                    ProgressView().controlSize(.small)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else if question.state == .unconfirmed {
                Label("Результат отправки неизвестен", systemImage: "questionmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if MobileReplyBuilder.supportsQuickReply(question) {
                quickReplies
            }
            if let failure = model.replyFailures[question.id] {
                ReplyFailureRow(sessionID: question.id, failure: failure)
            }
        }
        .padding(18)
        .mobileGlassCard(radius: 20)
    }

    private var summary: some View {
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
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Открыть вопрос")
    }

    private var quickReplies: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { quickReplyButtons(fill: false) }
            VStack(alignment: .leading, spacing: 8) { quickReplyButtons(fill: true) }
        }
    }

    private func quickReplyButtons(fill: Bool) -> some View {
        ForEach(question.options) { option in
            Button { model.quickReply(question, option: option) } label: {
                Text(option.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(fill ? 2 : 1)
                    .frame(maxWidth: fill ? .infinity : nil)
            }
            .buttonStyle(.bordered)
            .tint(MobilePalette.accent)
            .disabled(model.state != .connected)
            .accessibilityHint("Ответ уйдёт через 3 секунды, его можно отменить")
        }
    }
}

private struct UndoReplyBar: View {
    let pending: MobileUndoQueue.Pending
    let cancel: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let remaining = max(1, Int(pending.deadline.timeIntervalSince(context.date).rounded(.up)))
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Отправляем «\(pending.label)» через \(remaining)…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button("Отменить", action: cancel)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct QuestionView: View {
    @EnvironmentObject private var model: MobileAppModel
    @Environment(\.dismiss) private var dismiss
    let question: PingviQuestion
    @State private var answer = ""
    @State private var fieldAnswers: [String: String] = [:]
    @State private var multiAnswers: [String: Set<String>] = [:]

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
            if let failure = model.replyFailures[question.id] {
                Section { ReplyFailureRow(sessionID: question.id, failure: failure) }
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
                if !field.options.isEmpty {
                    if field.allowsMultiple {
                        multiSelectSection(field)
                    } else {
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
                }
            }
            Section("Короткий ответ") {
                TextField("Продиктуйте или введите ответ", text: $answer, axis: .vertical)
                    .lineLimit(2...6)
                Button(model.replyingSessions.contains(question.id) ? "Отправляем…" : "Отправить") { submit(answer: answer) }
                    .disabled(!canSubmit || (answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && collectedFieldAnswers.isEmpty))
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
        .mobileConnectionBanner()
        .navigationTitle(question.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть") { dismiss() }
            }
        }
    }

    private func multiSelectSection(_ field: PingviQuestionField) -> some View {
        Section {
            ForEach(field.options) { option in
                let selected = multiAnswers[field.id, default: []].contains(option.label)
                Button {
                    MobileHaptics.selection()
                    if selected { multiAnswers[field.id, default: []].remove(option.label) }
                    else { multiAnswers[field.id, default: []].insert(option.label) }
                } label: {
                    HStack {
                        Text(option.label).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? MobilePalette.accent : .secondary)
                    }
                }
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        } header: {
            Text(field.label)
        } footer: {
            Text("Можно выбрать несколько вариантов")
        }
    }

    private var collectedFieldAnswers: [String: String] {
        var result = fieldAnswers.filter { !$0.value.isEmpty }
        for field in question.fields where field.allowsMultiple {
            let joined = MobileReplyBuilder.joined(Array(multiAnswers[field.id, default: []]), in: field)
            if !joined.isEmpty { result[field.id] = joined }
        }
        return result
    }

    private var canSubmit: Bool {
        model.state == .connected && current?.canReply == true && !model.replyingSessions.contains(question.id)
    }

    private func submit(answer value: String) {
        let started = model.sendReply(PingviReply(
            sessionID: question.id,
            questionToken: question.token,
            answer: value.trimmingCharacters(in: .whitespacesAndNewlines),
            fieldAnswers: collectedFieldAnswers
        ))
        // The queue card takes over progress and failure reporting.
        if started { dismiss() }
    }
}

struct MobileSettingsView: View {
    @EnvironmentObject private var model: MobileAppModel
    @EnvironmentObject private var appearance: MobileAppearance
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appTheme") private var theme = MobileTheme.system.rawValue
    @AppStorage("fullNotificationPreviews") private var fullPreviews = false
    @State private var confirmForget = false

    private var themeTitle: String { (MobileTheme(rawValue: theme) ?? .system).title }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Mac", value: model.pairing?.peerName ?? String(localized: "Не подключён"))
                TimelineView(.everyMinute) { context in
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(model.state == .connected ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)
                                    .accessibilityHidden(true)
                                Text(model.state.description)
                            }
                            if let updated = MobileSyncText.updated(model.lastSyncAt, now: context.date) {
                                Text(updated).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } label: {
                        Text("Состояние")
                    }
                    .accessibilityElement(children: .combine)
                }
                if let fingerprint = model.pairing?.fingerprint {
                    LabeledContent("Отпечаток") {
                        Text(fingerprint)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                }
                Button("Забыть Mac…", role: .destructive) { confirmForget = true }
            } header: {
                Text("Подключение").accessibilityAddTraits(.isHeader)
            } footer: {
                Text("Отпечаток должен совпадать с показанным на Mac в Настройках → Подключения.")
            }

            Section {
                if model.notificationsAuthorized == false {
                    Label("Уведомления выключены в iOS", systemImage: "bell.slash.fill")
                        .foregroundStyle(.orange)
                    Button("Открыть настройки уведомлений") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                Toggle("Показывать текст вопроса", isOn: $fullPreviews)
            } header: {
                Text("Уведомления")
            } footer: {
                Text(model.notificationsAuthorized == false
                     ? "Без уведомлений Pingvi не сообщит о новых вопросах, пока приложение закрыто."
                     : "По умолчанию на заблокированном экране показывается только факт нового вопроса.")
            }

            Section {
                NavigationLink(value: MobileSettingsDestination.appearance) {
                    HStack(spacing: 12) {
                        Image(appearance.selectedIcon.previewName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .accessibilityHidden(true)
                        Text("Оформление")
                        Spacer()
                        Text("\(appearance.selectedIcon.title) · \(themeTitle)")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .accessibilityValue("\(appearance.selectedIcon.title), \(themeTitle)")
            } footer: {
                Text("Тема интерфейса и иконка приложения.")
            }

            Section {
                LabeledContent("Версия", value: version)
                Button("Скопировать диагностику") {
                    UIPasteboard.general.string = model.diagnostics()
                    model.showToast(String(localized: "Диагностика скопирована"), style: .success)
                }
            } header: {
                Text("О приложении")
            } footer: {
                Text("Тексты вопросов, ответы и ключи в диагностику не включаются.")
            }

            #if DEBUG
            Section {
                Label("Без Apple Developer Program приложение нужно переустанавливать через Xcode каждые 7 дней. Фоновая доставка в локальной сети не гарантируется.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif
        }
        .scrollContentBackground(.hidden)
        .background { MobileAmbientBackground() }
        .mobileConnectionBanner()
        .navigationTitle("Настройки")
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: MobileSettingsDestination.self) { destination in
            switch destination {
            case .appearance: MobileAppearanceSettingsView()
            }
        }
        .onAppear { model.refreshNotificationAuthorization() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshNotificationAuthorization() }
        }
        .alert("Забыть Mac?", isPresented: $confirmForget) {
            Button("Забыть", role: .destructive) { model.forgetMac() }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Для повторного подключения потребуется новый QR-код.") }
    }
}

struct MobileAppearanceSettingsView: View {
    @EnvironmentObject private var appearance: MobileAppearance
    @AppStorage("appTheme") private var theme = MobileTheme.system.rawValue

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
                                    .fixedSize(horizontal: false, vertical: true)
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
                if let error = appearance.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("iOS попросит подтвердить смену иконки. Выбор сохраняется после перезапуска.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { MobileAmbientBackground() }
        .navigationTitle("Оформление")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
