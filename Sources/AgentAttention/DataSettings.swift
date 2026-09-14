import SwiftUI
import AppKit

struct DataReport: Decodable { var bytes: Int64; var processed: Int; var pending: Int }
struct CleanupResult: Decodable { var cleaned: Int }

struct DataSettings: View {
    @ObservedObject var store: Store
    var preview = false
    @State private var report: DataReport?
    @State private var message: String?
    @State private var busy = false
    @State private var confirmChat = false
    @State private var confirmQuestions = false
    @State private var confirmReceipts = false
    var body: some View {
        Section("Локальное хранение") {
            Text("Pingvi сохраняет очередь, черновики и сведения об отправке на этом Mac. История читается из журналов агентов.")
            if let report {
                LabeledContent("Размер данных", value: ByteCountFormatter.string(fromByteCount: report.bytes, countStyle: .file))
                LabeledContent("Обработанные отправки с текстом", value: String(report.processed))
                LabeledContent("Отправки, требующие проверки", value: String(report.pending))
            }
            Button("Открыть папку данных") { NSWorkspace.shared.open(Bridge.root) }
            Button("Обновить сведения", action: refresh).disabled(busy)
            if let message { Text(message).font(.caption).textSelection(.enabled) }
        }
        Section("Очистка") {
            Button("Удалить черновики чата…", role: .destructive) { confirmChat = true }
                .confirmationDialog("Удалить черновики чата и недавние папки?", isPresented: $confirmChat, titleVisibility: .visible) {
                    Button("Удалить", role: .destructive) {
                        do { try ChatPreferences.shared.clearDrafts(); message = "Черновики чата и недавние папки удалены."; refresh() }
                        catch { message = error.localizedDescription }
                    }
                } message: { Text("Будут удалены неотправленные сообщения, первое сообщение нового диалога и список недавних папок.") }
            Button("Удалить черновики ответов на вопросы…", role: .destructive) { confirmQuestions = true }
                .disabled(!store.submitting.isEmpty)
                .confirmationDialog("Удалить черновики ответов на вопросы?", isPresented: $confirmQuestions, titleVisibility: .visible) {
                    Button("Удалить", role: .destructive) {
                        do { try store.clearQuestionDrafts(); message = "Черновики ответов удалены."; refresh() }
                        catch { message = error.localizedDescription }
                    }
                } message: { Text("Сохранённый текст и выбор вариантов будут удалены. Вопросы останутся в очереди; ответы агентам не отправляются.") }
            Button("Удалить тексты обработанных отправок…", role: .destructive) { confirmReceipts = true }
                .disabled(busy || report?.processed == 0 || report == nil)
                .confirmationDialog("Удалить тексты обработанных отправок?", isPresented: $confirmReceipts, titleVisibility: .visible) {
                    Button("Удалить", role: .destructive) { clean() }
                } message: { Text("Удаляются только локальные тексты подтверждённых или проверенных вами отправок. Неподтверждённые отправки сохраняются. Журналы агентов не изменяются.") }
            Text("Служебные записи без текста сохраняют защиту от повторной отправки. Отключить Claude можно в разделе «Подключения».").font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { refresh() }
    }
    private func refresh() {
        if preview { report = DataReport(bytes: 24576, processed: 12, pending: 1); return }
        guard !busy else { return }; busy = true
        Bridge.call(["action": "data-status"]) { result in
            busy = false
            do { report = try JSONDecoder().decode(DataReport.self, from: result.get()) }
            catch { message = error.localizedDescription }
        }
    }
    private func clean() {
        busy = true
        Bridge.call(["action": "data-clean"]) { result in
            busy = false
            do { let value = try JSONDecoder().decode(CleanupResult.self, from: result.get()); message = "Удалено текстов: \(value.cleaned)."; refresh() }
            catch { message = "Не удалось завершить очистку: " + error.localizedDescription; refresh() }
        }
    }
}
