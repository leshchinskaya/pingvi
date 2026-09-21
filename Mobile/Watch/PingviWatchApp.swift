import SwiftUI

@main
struct PingviWatchApp: App {
    @StateObject private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            WatchQueueView().environmentObject(store)
        }
    }
}
