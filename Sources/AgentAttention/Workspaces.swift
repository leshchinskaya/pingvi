import SwiftUI

struct WorkspaceSettings: View {
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var editing: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Рабочие пространства").font(.title2.bold())
                Spacer()
                Button("Готово") { dismiss() }
            }
            Text("Объединяйте диалоги разных агентов вокруг одной задачи. Добавить диалог можно через его контекстное меню.")
                .foregroundStyle(.secondary)
            HStack {
                TextField("Название задачи или пространства", text: $name)
                Button(editing == nil ? "Создать" : "Сохранить") {
                    store.saveWorkspace(id: editing, name: name)
                    name = ""; editing = nil
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if editing != nil { Button("Отмена") { editing = nil; name = "" } }
            }
            List(store.workspaces) { group in
                HStack {
                    VStack(alignment: .leading) {
                        Text(group.name)
                        Text("Диалогов: \(store.visible.filter { store.workspaceID($0) == group.id }.count)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Переименовать") { editing = group.id; name = group.name }
                    Button("Удалить") {
                        store.deleteWorkspace(group.id)
                        if editing == group.id { editing = nil; name = "" }
                    }
                }
            }
            Text("При удалении пространства диалоги остаются в общем списке.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 580, height: 400)
    }
}
