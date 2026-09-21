import SwiftUI

@main
struct PingviMobileApp: App {
    @UIApplicationDelegateAdaptor(MobileAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = MobileAppModel.shared
    @StateObject private var appearance = MobileAppearance.shared
    @AppStorage("appTheme") private var theme = MobileTheme.system.rawValue

    var body: some Scene {
        WindowGroup {
            MobileRootView()
                .environmentObject(model)
                .environmentObject(appearance)
                .environment(\.locale, documentationLocale)
                .preferredColorScheme(MobileTheme(rawValue: theme)?.colorScheme)
                .tint(MobilePalette.accent)
                .onAppear { appDelegate.model = model }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.activate()
            case .background: model.enteredBackground()
            default: break
            }
        }
    }

    private var documentationLocale: Locale {
        #if DEBUG
        if MobileDocumentationPreview.isEnabled { return Locale(identifier: "ru_RU") }
        #endif
        return .current
    }
}
