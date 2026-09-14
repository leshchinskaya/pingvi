import SwiftUI
import AppKit

struct ConnectionCheck: Decodable, Identifiable {
    var name: String
    var ready: Bool
    var detail: String
    var id: String { name }
}
struct ConnectionReport: Decodable { var checks: [ConnectionCheck] }

struct ConnectionsView: View {
    @ObservedObject var store: Store
    @AppStorage("claudePath") private var claude = ""
    @AppStorage("codexPath") private var codex = ""
    @AppStorage("herdrPath") private var herdr = ""
    @AppStorage("setupComplete") private var setupComplete = false
    @AppStorage("terminal") private var terminal = false
    @State private var checks: [ConnectionCheck] = []
    @State private var error: String?
    @State private var checking = false
    @State private var changingHooks = false
    var body: some View {
        Section("1. Проверка установки") {
            Text("Для начала достаточно одного агента: Claude Code или Codex. Для новых диалогов нужен herdr. CLI агентов должны быть установлены и авторизованы отдельно.")
            ForEach(checks) { check in
                VStack(alignment: .leading, spacing: 4) {
                    Label(check.name, systemImage: check.ready ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(check.ready ? Color.green : Color.orange)
                    Text(check.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
            Button(checking ? "Проверяем…" : "Проверить подключения", action: refresh).disabled(checking)
            DisclosureGroup("Пути к программам") {
                Text("Python входит в Pingvi и не требует отдельной установки.").font(.caption)
                TextField("Claude Code (пусто — найти автоматически)", text: $claude)
                TextField("Codex (пусто — найти автоматически)", text: $codex)
                TextField("herdr (пусто — найти автоматически)", text: $herdr)
                Text("Укажите полный путь к исполняемому файлу. Затем повторите проверку.").font(.caption)
            }
        }
        Section("2. Подключение Claude Code") {
            if Installation.needsMove() { Text(Installation.message).foregroundStyle(.orange) }
            Text("Установим обработчики вопросов с резервной копией настроек Claude. После подключения, обновления или отключения перезапустите существующие сессии Claude.")
            HStack {
                Button("Подключить / обновить") { hooks("install-hooks") }.disabled(Installation.needsMove())
                Button("Отключить") { hooks("uninstall-hooks") }
            }.disabled(changingHooks)
        }
        Section("3. Разрешения macOS") {
            Toggle("Читать вкладки Terminal", isOn: $terminal)
                .onChange(of: terminal) { _, _ in store.poll() }
            Button("Настройки автоматизации…") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!) }
            Text("Terminal нужен для обычных вкладок и перехода к исходному окну. Разрешение запрашивается при обращении к Terminal. Для очереди через herdr доступ к Универсальному доступу не требуется.").font(.caption)
            Button("Проверить уведомление") { store.testNotification() }
        }
        Section("4. Первый вопрос") {
            Text("Запустите агента в herdr, Apple Terminal или Claude в Warp и попросите задать вопрос. Откройте вопрос в Pingvi, ответьте и проверьте продолжение в исходном окне. Для Warp доступны вопросы Claude, история и переход к вкладке; новые сообщения вводите в Warp. iTerm и Ghostty пока не подключены.")
        }
        Section {
            Button(setupComplete ? "Настройка завершена" : "Завершить настройку") { setupComplete = true }
            Text("Завершайте настройку после проверки первого вопроса. К этим шагам можно вернуться в любое время.").font(.caption)
        }
        .onAppear { if checks.isEmpty { refresh() } }
    }
    private func refresh() {
        checking = true; error = nil
        Bridge.call(["action": "diagnostics"]) { result in
            checking = false
            do { checks = try JSONDecoder().decode(ConnectionReport.self, from: result.get()).checks }
            catch { self.error = error.localizedDescription }
        }
    }
    private func hooks(_ action: String) {
        changingHooks = true
        Bridge.call(["action": action]) { result in
            changingHooks = false
            switch result {
            case .success: store.message = "Настройки Claude обновлены. Перезапустите существующие сессии Claude."; refresh()
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }
}
