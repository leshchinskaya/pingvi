import SwiftUI
import AppKit
import UserNotifications
import ApplicationServices

func stateColor(_ status: String) -> Color {
    switch status { case "waiting", "unconfirmed": return Color(red: 0.96, green: 0.35, blue: 0.36)
    case "working": return .orange; case "done": return Color(red: 0.25, green: 0.78, blue: 0.53)
    case "checking": return Palette.accent
    default: return .secondary }
}
struct StatusDot: View {
    var status: String
    var body: some View { Circle().fill(stateColor(status)).frame(width: 9, height: 9).shadow(color: stateColor(status).opacity(0.4), radius: 4).accessibilityLabel(status) }
}
enum SessionFilter: String, CaseIterable {
    case all = "Все", waiting = "Ждут", working = "В работе", done = "Готово"
    func accepts(_ session: Session) -> Bool {
        switch self { case .all: return true; case .waiting: return session.waiting; case .working: return session.status == "working"; case .done: return session.status == "done" }
    }
}

struct ContentView: View {
    @ObservedObject var store: Store
    @ObservedObject private var iconAppearance = IconAppearance.shared
    var compact = false
    var onClose: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""
    @State private var workspace = "all"
    @State private var manageWorkspaces = false
    @State private var creatingWorkspace = false
    @State private var workspaceName = ""
    @State private var filter = SessionFilter.all
    @State private var showFinished = false
    @State private var inspecting = false
    @AppStorage("chatEnabled") private var chatEnabled = false
    @State private var newChat = false
    @State private var renamingSession: Session?
    @AppStorage("setupComplete") private var setupComplete = false
    @FocusState private var searching: Bool
    var workspaceSessions: [Session] {
        store.visible.filter { workspace == "all" || (workspace == "ungrouped" ? store.workspaceID($0) == nil : store.workspaceID($0) == workspace) }
    }
    var workspaceTitle: String {
        if workspace == "all" { return "Все пространства" }
        if workspace == "ungrouped" { return "Без пространства" }
        return store.workspaces.first { $0.id == workspace }?.name ?? "Все пространства"
    }
    var waitingCount: Int { workspaceSessions.filter { store.needsAttention($0) }.count }
    var searchQuery: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    var searchSessions: [Session] {
        workspaceSessions.filter { filter == .waiting ? store.needsAttention($0) : filter.accepts($0) }
    }
    var filtered: [Session] {
        searchSessions.filter { searchQuery.isEmpty || (store.title($0) + $0.project + $0.agent).localizedCaseInsensitiveContains(searchQuery) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: Brand.icon).resizable().scaledToFit().frame(width: 28, height: 28).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pingvi").font(.system(size: 16, weight: .semibold))
                    Text(store.pending.isEmpty ? "\(store.visible.count) диалогов" : "Ждут ответа: \(store.pending.count)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    if chatEnabled { ToolbarAction(symbol: "square.and.pencil", title: "Новый диалог") { newChat = true } }
                    if compact { ToolbarAction(symbol: "arrow.up.left.and.arrow.down.right", title: "Открыть большое окно") { store.showDashboard?() } }
                    ToolbarAction(symbol: "arrow.clockwise", title: "Обновить сессии", disabled: store.polling) { store.poll() }
                    ToolbarAction(symbol: "gearshape", title: "Настройки") { store.showSettings?() }
                    if let onClose { ToolbarAction(symbol: "xmark", title: "Закрыть панель", action: onClose) }
                }.padding(3).background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
            }.padding(.horizontal, 18).padding(.vertical, 12)
            Divider()
            if Installation.needsMove() {
                Text(Installation.message).font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.12))
            } else if !setupComplete {
                HStack {
                    Text("Первый запуск: проверьте подключения и разрешения.").font(.callout)
                    Spacer()
                    Button("Настроить") { store.showSettings?() }
                }.padding(12).background(Palette.accent.opacity(0.08))
            }
            if compact {
                if inspecting, let session = store.current {
                    HStack {
                        Button { inspecting = false } label: { Label("Все сессии", systemImage: "chevron.left") }.buttonStyle(.plain).foregroundStyle(Palette.accent)
                        Spacer()
                        if store.pending.count > 1 { Button("Следующий вопрос") { store.nextQuestion() }.buttonStyle(.plain).foregroundStyle(Palette.accent) }
                    }.font(.caption.weight(.medium)).padding(.horizontal, 20).padding(.vertical, 12)
                    SessionDetailView(store: store, session: session).id(session.id).padding(18).background(Palette.canvas)
                } else {
                    sidebar
                }
            } else {
                HSplitView {
                    sidebar.frame(minWidth: 270, idealWidth: 300, maxWidth: 340)
                    VStack(alignment: .leading, spacing: 0) {
                        if let session = store.current { SessionDetailView(store: store, session: session).id(session.id).padding(28) }
                        else { ContentUnavailableView("Ваши агенты — в одном месте", systemImage: "bubble.left.and.bubble.right", description: Text("Запускайте сессии как обычно. Когда агент задаст вопрос, он появится здесь.")) }
                    }.frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity).background(Palette.canvas)
                }
            }
            if let message = store.message {
                HStack(alignment: .top) { Image(systemName: "info.circle"); Text(message).font(.caption).textSelection(.enabled); Spacer(); Button { store.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Скрыть сообщение") }.padding(12).background(Palette.accent.opacity(0.08))
            }
            if !store.errors.isEmpty {
                DisclosureGroup {
                    ForEach(store.errors, id: \.self) { Text($0).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4) }
                    Button("Настроить подключения") { store.showSettings?() }.controlSize(.small)
                } label: {
                    Label("Подключение требует внимания", systemImage: "exclamationmark.circle").font(.caption)
                }.foregroundStyle(.secondary).padding(12)
            }
        }.background { AmbientBackground() }.tint(Palette.accent)
            .alert("Новое пространство", isPresented: $creatingWorkspace) {
                TextField("Название", text: $workspaceName)
                Button("Создать") {
                    store.saveWorkspace(name: workspaceName)
                    if let created = store.workspaces.last { workspace = created.id }
                }.disabled(workspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Отмена", role: .cancel) {}
            } message: { Text("Объедините диалоги вокруг одной задачи.") }
            .sheet(isPresented: $manageWorkspaces) { WorkspaceSettings(store: store) }
            .onChange(of: workspace) { _, _ in
                if !filtered.contains(where: { $0.id == store.selected }) { store.selected = filtered.first?.id }
            }
            .onChange(of: store.local.workspaceAssignments) { _, _ in
                if !filtered.contains(where: { $0.id == store.selected }) { store.selected = filtered.first?.id }
            }
            .onChange(of: store.workspaces) { _, groups in
                if workspace != "all" && workspace != "ungrouped" && !groups.contains(where: { $0.id == workspace }) { workspace = "all" }
            }
            .sheet(isPresented: $newChat) { NewChatView(store: store) }
            .sheet(item: $renamingSession) { session in
                RenameSessionView(store: store, session: session)
            }
            .onChange(of: chatEnabled) { _, enabled in if !enabled { newChat = false } }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Диалоги").font(.system(size: 18, weight: .bold)).fixedSize()
                Spacer(minLength: 0)
                Menu {
                    Picker("Пространство", selection: $workspace) {
                        Text("Все пространства").tag("all")
                        Text("Без пространства").tag("ungrouped")
                        ForEach(store.workspaces) { group in Text(group.name).tag(group.id) }
                    }
                    Divider()
                    Button("Создать пространство…") { workspaceName = ""; creatingWorkspace = true }
                    Button("Управлять пространствами…") { manageWorkspaces = true }
                } label: {
                    HStack(spacing: 4) {
                        Text(workspaceTitle).lineLimit(1).truncationMode(.tail)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }.font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.accent).padding(.vertical, 7)
                        .contentShape(Rectangle())
                }.menuStyle(.borderlessButton).menuIndicator(.hidden)
                    .fixedSize(horizontal: false, vertical: true)
                    .help("Пространство: " + workspaceTitle)
                    .accessibilityLabel("Выбрать пространство: " + workspaceTitle)
            }.padding(.top, 4)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Поиск диалогов и сообщений", text: $search).textFieldStyle(.plain).focused($searching)
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary).help("Очистить поиск") }
            }.padding(10).background(Palette.input, in: RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 4) {
                ForEach(SessionFilter.allCases, id: \.self) { item in
                    Button { filter = item } label: {
                        HStack(spacing: 4) {
                            Text(item.rawValue)
                            if item == .waiting && waitingCount > 0 {
                                Text("\(waitingCount)").font(.system(size: 9, weight: .semibold).monospacedDigit())
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(filter == .waiting ? Color.white.opacity(0.2) : Palette.accent.opacity(0.12), in: Capsule())
                            }
                        }.font(.system(size: 11, weight: filter == item ? .semibold : .regular))
                            .padding(.vertical, 7).frame(maxWidth: .infinity)
                            .background(filter == item ? Palette.action : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(filter == item ? Color.white : Color.secondary)
                    }.buttonStyle(.plain).accessibilityAddTraits(filter == item ? .isSelected : [])
                }
            }.padding(3).background(Palette.input, in: RoundedRectangle(cornerRadius: 11))
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    sessionList
                    if !searchQuery.isEmpty {
                        ConversationSearchView(store: store, sessions: searchSessions, query: searchQuery)
                    }
                }.padding(.bottom, 8)
            }.scrollIndicators(.hidden)
            HStack(spacing: 6) {
                Circle().fill(store.errors.isEmpty ? Color.green : Color.orange).frame(width: 5, height: 5)
                Text(store.lastUpdate == nil ? "Подключаемся…" : "Обновляется автоматически").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text("⌘F").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Button("") { searching = true }.keyboardShortcut("f", modifiers: .command).hidden().frame(height: 0)
        }.padding(14).background(LinearGradient(colors: [Palette.sidebar, Palette.canvas], startPoint: .topLeading, endPoint: .bottomTrailing))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: filter)
    }
    var sessionList: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            let waiting = filtered.filter { store.needsAttention($0) }
            if !waiting.isEmpty {
                sectionLabel("Нужен ответ", count: waiting.count)
                ForEach(waiting) { row($0) }
            }
            let active = filtered.filter { !store.needsAttention($0) && !["done", "viewed"].contains($0.status) }
            if !active.isEmpty { sectionLabel("Остальные диалоги", count: active.count).padding(.top, waiting.isEmpty ? 0 : 12) }
            ForEach(active) { row($0) }
            let finished = filtered.filter { ["done", "viewed"].contains($0.status) }
            if !finished.isEmpty {
                if filter == .done { ForEach(finished) { row($0) } }
                else { DisclosureGroup("Завершённые · \(finished.count)", isExpanded: $showFinished) { ForEach(finished) { row($0) } }.font(.caption).padding(.top, 12) }
            }
            if filtered.isEmpty && !searchQuery.isEmpty {
                Text("По названию или проекту совпадений нет").font(.caption).foregroundStyle(.secondary)
            } else if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: search.isEmpty ? "checkmark.bubble" : "magnifyingglass").font(.system(size: 28)).foregroundStyle(Palette.accent.opacity(0.7))
                    Text(search.isEmpty ? (filter == .waiting ? "Ответов не ждут" : "Здесь пока пусто") : "Ничего не найдено").font(.headline)
                    Text(search.isEmpty ? "Новые события появятся автоматически." : "Попробуйте другое название или проект.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if filter != .all { Button("Все сессии") { filter = .all }.buttonStyle(.bordered) }
                }.frame(maxWidth: .infinity).padding(.vertical, 35)
            }
        }
    }
    func sectionLabel(_ title: String, count: Int) -> some View {
        HStack { Text(title); Spacer(); Text("\(count)") }.font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 3).padding(.vertical, 3)
    }
    func row(_ s: Session) -> some View {
        Button { store.choose(s); inspecting = true } label: {
            HStack(alignment: .top, spacing: 10) {
                StatusDot(status: store.isRead(s) ? "viewed" : s.status).padding(.top, 4).help(s.question.isEmpty ? s.statusLabel : s.question)
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.title(s)).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    Text(s.agent.capitalized + " · " + (s.project.isEmpty ? s.source : URL(fileURLWithPath: s.project).lastPathComponent)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    if let group = store.workspaces.first(where: { $0.id == store.workspaceID(s) }) {
                        Label(group.name, systemImage: "folder").font(.caption2).foregroundStyle(Palette.accent)
                    }
                    if s.waiting && !s.question.isEmpty { Text(s.question).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2) }
                    HStack(spacing: 4) {
                        Text(store.isRead(s) ? "Прочитано · можно ответить позже" : s.statusLabel).lineLimit(1)
                        if let at = store.local.arrival[s.token], s.waiting { Text("·"); Text(Date(timeIntervalSince1970: at), style: .relative).lineLimit(1) }
                    }.font(.system(size: 10)).foregroundStyle(stateColor(store.isRead(s) ? "viewed" : s.status))
                    if let due = store.local.snoozes[s.token] {
                        Label("Напомнить в " + Date(timeIntervalSince1970: due).formatted(date: .omitted, time: .shortened), systemImage: "clock").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if compact { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary).padding(.top, 3) }
            }.padding(.horizontal, 11).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                .background(store.selected == s.id ? Palette.selection : .clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .leading) { if store.selected == s.id { Capsule().fill(Palette.accent).frame(width: 3, height: 28) } }
        }.buttonStyle(.plain).contextMenu {
            SessionReadAction(store: store, session: s)
            Button("Переименовать") { renamingSession = s }
            Menu("Рабочее пространство") {
                Button("Без пространства") { store.assign(s, to: nil) }
                ForEach(store.workspaces) { group in
                    Button(group.name) { store.assign(s, to: group.id) }
                }
                Divider()
                Button("Управлять пространствами…") { manageWorkspaces = true }
            }
            Button("Открыть сессию") { store.open(s) }
            Button("Исключить сессию") { store.exclude(s) }
            if !s.project.isEmpty { Button("Исключить проект") { store.exclude(s, project: true) } }
            if ["done", "viewed"].contains(s.status) { Button("Убрать из списка") { store.retire(s) } }
        }
    }
}

struct SessionReadAction: View {
    @ObservedObject var store: Store
    let session: Session
    var body: some View {
        if session.status == "waiting" || session.status == "done" {
            Button { store.toggleRead(session) } label: {
                Label(store.isRead(session) ? "Вернуть в непрочитанные" : "Отметить прочитанной",
                      systemImage: store.isRead(session) ? "envelope.badge" : "envelope.open")
            }
        }
    }
}

struct RenameSessionView: View {
    @ObservedObject var store: Store
    let session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @FocusState private var editing: Bool

    init(store: Store, session: Session) {
        self.store = store
        self.session = session
        _name = State(initialValue: store.title(session))
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Переименовать сессию").font(.headline)
            TextField("Название", text: $name).focused($editing)
                .onSubmit { save() }
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }.padding(24).frame(width: 360)
            .onAppear { editing = true }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        store.local.names[session.id] = trimmedName
        store.save()
        dismiss()
    }
}

struct QuestionView: View {
    @ObservedObject var store: Store
    var session: Session
    var compact = false
    var selectQuestion: ((String) -> Void)? = nil
    @State private var details = false
    @State private var renaming = false
    @State private var newName = ""
    private var projectLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
            Text(session.project.isEmpty ? session.source : URL(fileURLWithPath: session.project).lastPathComponent).lineLimit(1)
            Text("· " + session.agent.capitalized).lineLimit(1)
        }.font(.caption).foregroundStyle(.secondary).help(session.project).textSelection(.enabled)
    }
    private var queueItems: some View {
        ForEach(store.pending) { item in
            Button(store.title(item)) { selectQuestion?(item.id) }
        }
    }
    func selected(_ option: FieldOption, in field: QuestionField) -> Bool {
        let draft = store.draft(session, field: field.id)
        return field.multi ? draft.components(separatedBy: ", ").contains(option.label) : draft == option.label
    }
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 15) {
            if compact {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.title(session)).font(.system(size: 18, weight: .semibold))
                            .lineLimit(1).help(store.title(session)).textSelection(.enabled)
                        projectLabel
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: session.waiting ? "hand.raised.fill" : "circle.fill")
                        .font(.caption).foregroundStyle(stateColor(session.status))
                        .help(session.statusLabel).accessibilityLabel(session.statusLabel)
                        .padding(.top, 4)
                    if store.pending.count > 1 {
                        Menu {
                            queueItems
                        } label: {
                            Text("\((store.pending.firstIndex { $0.id == session.id } ?? 0) + 1) из \(store.pending.count)")
                                .font(.caption)
                        }.menuStyle(.borderlessButton).fixedSize().help("Очередь вопросов")
                    }
                    Menu {
                        if store.pending.count <= 1 { Menu("Очередь") { queueItems } }
                        Button("Переименовать") { newName = store.title(session); renaming = true }
                        Button("Исключить") { store.exclude(session) }
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).frame(width: 22)
                }.fixedSize(horizontal: false, vertical: true)
            } else {
                HStack {
                    Label(session.statusLabel, systemImage: session.waiting ? "hand.raised.fill" : "circle.fill").font(.caption.weight(.semibold)).foregroundStyle(stateColor(session.status)).padding(.horizontal, 10).padding(.vertical, 6).background(stateColor(session.status).opacity(0.08), in: Capsule())
                    Spacer()
                    Menu { Button("Переименовать") { newName = store.title(session); renaming = true }; Button("Исключить") { store.exclude(session) } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 22)
                }
                Text(store.title(session)).font(.system(size: 23, weight: .semibold)).textSelection(.enabled)
                projectLabel
            }
            SessionReadAction(store: store, session: session)
            if renaming {
                HStack { TextField("Название", text: $newName); Button("Сохранить") { store.local.names[session.id] = newName; store.save(); renaming = false } }
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if session.waiting { QuestionContextView(session: session) }
                    if !session.question.isEmpty && (session.fields.isEmpty || session.kind != "hook") {
                        if session.kind == "screen" && !compact {
                            RecentContextView(text: session.question, previous: session.options.isEmpty ? store.local.answeredContext?[session.id] : nil)
                        } else { FormattedMessage(text: session.question) }
                    }
                    if !session.waiting && session.status != "offline" {
                        VStack(spacing: 16) {
                            Image(systemName: session.status == "working" ? "sparkles" : (session.status == "done" ? "checkmark.bubble.fill" : "bubble.left.and.bubble.right"))
                                .font(.system(size: 25, weight: .regular)).foregroundStyle(Palette.accent)
                                .frame(width: 58, height: 58).background(Palette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 24))
                            Text(session.status == "working" ? "Агент занят задачей" : (session.status == "done" ? "Ответ готов" : "Можно продолжить диалог")).font(.title3.weight(.semibold))
                            Text(session.status == "working" ? "Если понадобится ваш ответ, вопрос появится в очереди." : "Откройте исходную сессию, чтобы прочитать результат или задать новую задачу.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 330)
                            if !store.pending.isEmpty { Button("Перейти к ожидающему вопросу") { store.nextQuestion() }.buttonStyle(.bordered) }
                        }.frame(maxWidth: .infinity).padding(.vertical, 24)
                    }
                    if session.status == "offline" { Label("Последнее обновление: " + Date(timeIntervalSince1970: session.updated).formatted(date: .omitted, time: .shortened), systemImage: "wifi.slash").foregroundStyle(.secondary) }
                    ForEach(session.fields) { field in
                        VStack(alignment: .leading, spacing: 8) {
                            FormattedMessage(text: field.label).fontWeight(.semibold)
                            ForEach(field.options, id: \.label) { option in
                                Button {
                                    if field.multi {
                                        var values = store.draft(session, field: field.id).components(separatedBy: ", ").filter { !$0.isEmpty }
                                        if values.contains(option.label) { values.removeAll { $0 == option.label } } else { values.append(option.label) }
                                        store.setDraft(session, field: field.id, value: values.joined(separator: ", "))
                                    } else { store.setDraft(session, field: field.id, value: selected(option, in: field) ? "" : option.label) }
                                } label: {
                                    HStack(alignment: .top, spacing: 9) {
                                        Image(systemName: selected(option, in: field) ? (field.multi ? "checkmark.square.fill" : "checkmark.circle.fill") : (field.multi ? "square" : "circle")).foregroundStyle(selected(option, in: field) ? Palette.accent : Color.secondary).padding(.top, 2)
                                        VStack(alignment: .leading, spacing: 4) { FormattedMessage(text: option.label).fontWeight(.medium); if let description = option.description { FormattedMessage(text: description, size: 12).foregroundStyle(.secondary) } }.frame(maxWidth: .infinity, alignment: .leading)
                                    }.padding(14).surface(radius: 16, selected: selected(option, in: field))
                                }.buttonStyle(.plain).disabled(!session.canReply || store.submitting.contains(session.id)).accessibilityAddTraits(selected(option, in: field) ? .isSelected : [])
                            }
                            MessageComposer(placeholder: field.options.isEmpty ? "Ваш ответ…" : "Дополнить ответ…", text: Binding(
                                get: { field.options.isEmpty ? store.draft(session, field: field.id) : store.comment(session, field: field.id) },
                                set: { if field.options.isEmpty { store.setDraft(session, field: field.id, value: $0) } else { store.setComment(session, field: field.id, value: $0) } }
                            ), canSend: session.canReply && !store.answers(session).values.contains { $0.isEmpty },
                                sending: store.submitting.contains(session.id), showsSend: field.id == session.fields.last?.id) {
                                store.reply(session)
                            }.padding(12).background(Palette.input.opacity(0.45), in: RoundedRectangle(cornerRadius: 10)).disabled(!session.canReply || store.submitting.contains(session.id))
                            if !field.options.isEmpty { Text("Можно дополнить выбранный вариант или написать свой ответ.").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    if !session.fields.isEmpty {
                        HStack {
                            Text("Enter — отправить · Shift+Enter — новая строка").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            if session.fields.contains(where: { !store.draft(session, field: $0.id).isEmpty || !store.comment(session, field: $0.id).isEmpty }) { Label("Черновик сохранён", systemImage: "checkmark").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                    if !session.detail.isEmpty {
                        DisclosureGroup("Подробности действия и контекст", isExpanded: $details) {
                            VStack(alignment: .leading, spacing: 8) {
                                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(session.detail, forType: .string) } label: { Label("Копировать", systemImage: "doc.on.doc") }.controlSize(.small)
                                if session.kind == "screen" {
                                    RecentContextView(text: session.detail, previous: session.options.isEmpty ? store.local.answeredContext?[session.id] : nil, monospaced: true)
                                } else { FormattedMessage(text: session.detail, size: 11, monospaced: true) }
                            }.padding(12).background(Palette.sidebar.opacity(0.6), in: RoundedRectangle(cornerRadius: 10)).padding(.top, 8)
                        }.font(.caption)
                    }
                }
            }.frame(minHeight: 90, maxHeight: .infinity)
            if session.status == "unconfirmed" {
                Text("Ответ отправлен. Подтверждения от агента пока нет; автоматического повтора не будет.").font(.caption).foregroundStyle(.orange)
                Button("Проверено в сессии — обновить вопрос") { store.clearUncertain(session) }.controlSize(.small)
            }
            if session.status == "checking" { Label("Ответ отправлен. Проверяем состояние агента…", systemImage: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(Palette.accent) }
            if !session.options.isEmpty {
                VStack(spacing: 7) { ForEach(session.options) { option in
                    Button { store.reply(session, answer: option.id) } label: { FormattedMessage(text: option.label).multilineTextAlignment(.leading).lineLimit(nil).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3) }.buttonStyle(.bordered).disabled(!session.canReply || store.submitting.contains(session.id))
                } }.fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button { store.open(session) } label: { Label(compact ? "В сессию" : "Открыть сессию", systemImage: "arrow.up.forward.app").foregroundStyle(compact ? Color.secondary : Palette.accent) }.buttonStyle(.plain)
                Spacer()
                if session.waiting {
                    Menu { ForEach([5, 15, 30, 60], id: \.self) { minutes in Button("Через \(minutes) мин") { store.snooze(session, minutes: Double(minutes)) } } } label: { Label("Позже", systemImage: "clock") }.menuStyle(.borderlessButton).fixedSize().help("Напомнить об этом вопросе позже")
                    Button("Скрыть") { store.dismiss(session) }.help("Убрать карточку, сохранив вопрос в очереди")
                }
            }.controlSize(compact ? .small : .regular).font(compact ? .caption : .body)
                .foregroundStyle(compact ? Color.secondary : Color.primary)
                .padding(.top, compact ? 0 : 6).fixedSize(horizontal: false, vertical: true)
        }.onAppear { store.separateLegacyComments(session) }
            .onChange(of: session.token) { _, _ in store.separateLegacyComments(session) }
    }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "Основные", appearance = "Облик", notifications = "Уведомления", connections = "Подключения", exclusions = "Исключения", data = "Данные"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .general: return "gearshape"; case .appearance: return "paintpalette"; case .notifications: return "bell.badge"; case .connections: return "point.3.connected.trianglepath.dotted"; case .data: return "internaldrive"; case .exclusions: return "eye.slash" }
    }
}

private struct SettingsSectionIcon: View {
    let page: SettingsPage
    @Environment(\.colorScheme) private var scheme
    private var ink: Color {
        scheme == .dark ? Color(red: 0.70, green: 0.84, blue: 1) : Palette.navy
    }
    var body: some View {
        Image(systemName: page.symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(ink)
            .frame(width: 24, height: 24)
            .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(ink.opacity(0.16), lineWidth: 0.75)
            }
            .accessibilityHidden(true)
    }
}

struct SettingsView: View {
    @ObservedObject var store: Store
    var preview = false
    @ObservedObject private var appearance = IconAppearance.shared
    @State private var page: SettingsPage? = UserDefaults.standard.bool(forKey: "setupComplete") ? .general : .connections
    @State private var search = ""
    @State private var notificationStatus = "Проверяем…"
    @AppStorage("dock") private var dock = true
    @AppStorage("menubar") private var menubar = true
    @AppStorage("questionNotifications") private var questions = true
    @AppStorage("completionNotifications") private var completions = true
    @AppStorage("floating") private var floating = false
    @AppStorage("terminal") private var terminal = false
    @AppStorage("chatEnabled") private var chatEnabled = false
    @AppStorage("appTheme") private var theme = AppTheme.system.rawValue
    var matchingPages: [SettingsPage] {
        SettingsPage.allCases.filter { search.isEmpty || ($0.rawValue + keywords($0)).localizedCaseInsensitiveContains(search) }
    }
    func keywords(_ page: SettingsPage) -> String {
        switch page {
        case .general: return " Dock меню видимость наведение доступ чат переписка сообщения"
        case .appearance: return " иконка пингвин тема светлая тёмная ночь"
        case .notifications: return " вопросы завершение карточка поверх окон разрешения"
        case .connections: return " herdr Claude Codex Terminal автоматизация"
        case .data: return " данные очистка черновики хранение удалить приватность"
        case .exclusions: return " скрытые проекты сессии"
        }
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(nsImage: Brand.icon).resizable().frame(width: 32, height: 32)
                    VStack(alignment: .leading) { Text("Pingvi").font(.headline); Text("Настройки").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                }.padding(.horizontal, 12).padding(.top, 12)
                TextField("Поиск", text: $search).textFieldStyle(.roundedBorder).padding(.horizontal, 10)
                List(matchingPages, selection: $page) { item in
                    Label {
                        Text(item.rawValue)
                    } icon: {
                        SettingsSectionIcon(page: item)
                    }.padding(.vertical, 3).tag(item)
                }.listStyle(.sidebar).scrollContentBackground(.hidden)
            }.frame(width: 210).frame(maxHeight: .infinity)
                .background(LinearGradient(colors: [Palette.sidebar, Palette.canvas], startPoint: .topLeading, endPoint: .bottomTrailing))
            Divider()
            VStack(spacing: 0) {
                HStack { Text((page ?? .general).rawValue).font(.system(size: 26, weight: .bold, design: .rounded)); Spacer() }.padding(22)
                if page == .exclusions && store.local.excluded.isEmpty && store.local.excludedProjects.isEmpty {
                    ContentUnavailableView("Исключений нет", systemImage: "eye", description: Text("Скрытые проекты и сессии появятся здесь. Их можно будет вернуть в список."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                Form {
                    switch page ?? .general {
                    case .general: general
                    case .appearance:
                        Section {
                            Picker("Тема", selection: $theme) {
                                ForEach(AppTheme.allCases) { theme in
                                    Text(theme.title).tag(theme.rawValue)
                                }
                            }.pickerStyle(.segmented)
                        } header: { Text("Тема интерфейса") } footer: {
                            Text("Применяется ко всем окнам и панелям. «Как в macOS» автоматически следует системной теме.")
                        }
                        Section("Иконка") { MoodPickerView() }
                    case .notifications: notifications
                    case .connections: ConnectionsView(store: store)
                    case .data: DataSettings(store: store)
                    case .exclusions: exclusions
                    }
                }.formStyle(.grouped).scrollContentBackground(.hidden)
                }
                if let message = store.message {
                    HStack { Text(message).font(.caption); Spacer(); Button { store.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                        .padding(12).background(.quaternary)
                }
            }.background { AmbientBackground() }
        }.tint(Palette.accent)
            .onChange(of: search) { _, _ in if let first = matchingPages.first, !matchingPages.contains(page ?? .general) { page = first } }
            .onChange(of: dock) { _, _ in store.onChange?() }
            .onChange(of: menubar) { _, _ in store.onChange?() }
            .onChange(of: terminal) { _, _ in store.poll() }
            .onChange(of: theme) { _, _ in store.onChange?() }
            .onAppear { if !preview { refreshAuthorization() } }
    }
    var general: some View {
        Group {
            Section {
                Toggle("Чат в Pingvi", isOn: $chatEnabled)
            } header: { Text("Переписка с агентами") } footer: { Text("Читайте ответы, отправляйте сообщения и создавайте диалоги в herdr. Выключение скрывает чат, сохраняя черновики, сессии и уведомления.") }
            Section {
                Toggle("Показывать в Dock", isOn: $dock).disabled(!menubar)
                Toggle("Показывать в строке меню", isOn: $menubar).disabled(!dock)
            } header: { Text("Быстрый доступ") } footer: { Text("Оставьте хотя бы один способ открыть Pingvi.") }
            Section {
                LabeledContent("Список при наведении на Dock") {
                    Button("Разрешить…") {
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                        _ = AXIsProcessTrustedWithOptions(options)
                    }
                }
            } footer: { Text("Нужен «Универсальный доступ». Список в строке меню доступен без дополнительного разрешения.") }
            Section { LabeledContent("Версия", value: "0.7.0-beta.6"); Text("Изменения сохраняются автоматически.").foregroundStyle(.secondary) }
        }
    }
    var notifications: some View {
        Group {
            Section {
                Toggle("Агент ждёт ответа", isOn: $questions)
                Toggle("Агент завершил задачу", isOn: $completions)
            } header: { Text("Системные уведомления") } footer: { Text("Вопросы и готовые результаты настраиваются независимо.") }
            Section {
                Toggle("Показывать карточку поверх окон", isOn: $floating)
            } header: { Text("Вопросы") } footer: { Text("Карточка открывается автоматически, не забирая фокус клавиатуры. Остальные вопросы остаются в очереди.") }
            Section {
                LabeledContent("Разрешение macOS", value: notificationStatus)
                HStack {
                    Button("Настройки macOS…") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!) }
                    Spacer()
                    Button("Тестовое уведомление") { store.testNotification(); refreshAuthorization() }
                }
            } footer: { Text("Стиль баннеров и режим «Фокусирование» управляются в настройках macOS.") }
        }
    }
    var connections: some View {
        Group {
            Section("herdr") { LabeledContent("Подключение", value: "Автоматически"); Text("Сессии Claude и Codex появляются после запуска в herdr.").foregroundStyle(.secondary) }
            Section {
                LabeledContent("Claude Code") { Button("Подключить…") { store.installHooks() } }
            } footer: { Text("Установит обработчики событий и сохранит резервную копию настроек Claude. Уже открытые сессии нужно перезапустить.") }
            Section {
                Toggle("Читать вкладки Terminal", isOn: $terminal)
                Button("Разрешения автоматизации…") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!) }
            } header: { Text("Terminal") } footer: { Text("Доступ нужен для обнаружения обычных сессий и перехода к нужному окну.") }
        }
    }
    var exclusions: some View {
        Group {
            if store.local.excluded.isEmpty && store.local.excludedProjects.isEmpty {
                ContentUnavailableView("Исключений нет", systemImage: "eye", description: Text("Скрытые проекты и сессии появятся здесь. Их можно будет вернуть в список."))
            } else {
                Section("Сессии") {
                    ForEach(Array(store.local.excluded).sorted(), id: \.self) { id in
                        LabeledContent(store.local.sessions.first(where: { $0.id == id }).map { store.title($0) } ?? id) {
                            Button("Вернуть") { store.local.excluded.remove(id); store.save() }
                        }
                    }
                }
                Section("Проекты") {
                    ForEach(Array(store.local.excludedProjects).sorted(), id: \.self) { project in
                        LabeledContent(project) { Button("Вернуть") { store.local.excludedProjects.remove(project); store.save() } }
                    }
                }
            }
        }
    }
    func refreshAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus { case .authorized, .provisional, .ephemeral: notificationStatus = "Разрешены"; case .denied: notificationStatus = "Выключены"; default: notificationStatus = "Не запрошено" }
            }
        }
    }
}

struct MoodPickerView: View {
    @ObservedObject private var appearance = IconAppearance.shared
    @AppStorage("iconMode") private var mode = "system"
    @AppStorage("iconManual") private var manual = "Ice"
    @AppStorage("iconLight") private var light = "Ice"
    @AppStorage("iconDark") private var dark = "Night"
    @State private var editingTheme = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
    var choice: Binding<String> {
        if mode == "manual" { return $manual }
        return editingTheme == "light" ? $light : $dark
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: appearance.selected.image).resizable().scaledToFit().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Сейчас: " + appearance.selected.title).font(.headline)
                    Text(mode == "system" ? "Меняется вместе с темой интерфейса" : "Один облик для любого настроения").font(.caption).foregroundStyle(.secondary)
                }
            }
            Picker("Режим", selection: $mode) { Text("Один облик").tag("manual"); Text("По теме интерфейса").tag("system") }.pickerStyle(.segmented)
            if mode == "system" {
                Picker("Выбрать для темы", selection: $editingTheme) {
                    Text("☀ Светлая").tag("light"); Text("☾ Тёмная").tag("dark")
                }.pickerStyle(.segmented)
                Text("Светлая — \(IconMood(rawValue: light)?.title ?? "Лёд") · Тёмная — \(IconMood(rawValue: dark)?.title ?? "Ночь")").font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 12) {
                ForEach(IconMood.allCases) { mood in
                    Button { choice.wrappedValue = mood.rawValue } label: {
                        VStack(spacing: 7) {
                            Image(nsImage: mood.image).resizable().scaledToFit().frame(width: 70, height: 70)
                            HStack(spacing: 4) { Text(mood.title).font(.caption.weight(.semibold)); if choice.wrappedValue == mood.rawValue { Image(systemName: "checkmark.circle.fill").font(.caption) } }
                            Text(mood.caption).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(height: 28)
                        }.frame(maxWidth: .infinity).padding(9)
                            .surface(radius: 20, selected: choice.wrappedValue == mood.rawValue)
                    }.buttonStyle(.plain).accessibilityLabel(mood.title).accessibilityAddTraits(choice.wrappedValue == mood.rawValue ? .isSelected : [])
                }
            }
            Text("Облик меняет иконку в Dock и интерфейсе. В строке меню — лаконичный силуэт. Системные уведомления используют постоянную иконку Pingvi.").font(.caption).foregroundStyle(.secondary)
        }.onChange(of: mode) { _, _ in appearance.refresh() }
            .onChange(of: manual) { _, _ in appearance.refresh() }
            .onChange(of: light) { _, _ in appearance.refresh() }
            .onChange(of: dark) { _, _ in appearance.refresh() }
    }
}
