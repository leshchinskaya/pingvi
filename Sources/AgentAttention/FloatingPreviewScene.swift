import SwiftUI

/// The production question view on a fictional desktop, for public documentation.
/// No screen capture, session polling or external application is involved.
struct FloatingPreviewScene: View {
    let store: Store
    let id: String

    private func titlebar(_ title: String, dark: Bool = false) -> some View {
        HStack(spacing: 8) {
            ForEach([Color.red, .yellow, .green], id: \.self) { color in
                Circle().fill(color.opacity(0.85)).frame(width: 10, height: 10)
            }
            Spacer()
            Text(title).font(.system(size: 12, weight: .medium))
            Spacer()
            Color.clear.frame(width: 46, height: 10)
        }
        .padding(.horizontal, 16).frame(height: 34)
        .foregroundStyle(dark ? Color.white.opacity(0.65) : Color.secondary)
        .background(dark ? Color(red: 0.13, green: 0.15, blue: 0.22) : Color(red: 0.95, green: 0.96, blue: 0.98))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.83, green: 0.88, blue: 1), Color(red: 0.92, green: 0.86, blue: 0.97)], startPoint: .topLeading, endPoint: .bottomTrailing)

            VStack(alignment: .leading, spacing: 0) {
                titlebar("Aurora — ProfileView.swift", dark: true)
                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("AURORA").font(.caption.bold())
                        Label("Sources", systemImage: "folder")
                        Text("  ProfileView.swift").foregroundStyle(.white)
                        Text("  ActivityCard.swift")
                        Text("  Theme.swift")
                        Label("Tests", systemImage: "folder")
                    }.font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).frame(width: 155, alignment: .leading)
                    Text("import SwiftUI\n\nstruct ProfileView: View {\n    var body: some View {\n        VStack(spacing: 24) {\n            ProfileHeader()\n            ActivityFeed()\n        }\n        .padding(32)\n    }\n}")
                        .font(.system(size: 15, design: .monospaced)).lineSpacing(9)
                        .foregroundStyle(Color(red: 0.71, green: 0.8, blue: 1))
                    Spacer()
                }.padding(24)
                Spacer()
                Divider().overlay(.white.opacity(0.12))
                VStack(alignment: .leading, spacing: 12) {
                    Text("TERMINAL   ·   Claude Code").font(.system(size: 11, weight: .semibold))
                    Text("› Добавь ленту активности в профиль\n\n  Уточняю компоновку перед реализацией…")
                        .font(.system(size: 13, design: .monospaced)).lineSpacing(7)
                }.foregroundStyle(.white.opacity(0.6)).padding(24)
            }
            .frame(width: 860, height: 610)
            .background(Color(red: 0.09, green: 0.11, blue: 0.17))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.18), radius: 20, y: 12)
            .offset(x: 38, y: 70)

            VStack(spacing: 0) {
                titlebar("Нужен ваш ответ")
                FloatingQuestion(store: store, id: id).frame(width: 440, height: 550)
            }
            .frame(width: 440)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.8), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 28, y: 16)
            .offset(x: 640, y: 108)
        }
    }
}
