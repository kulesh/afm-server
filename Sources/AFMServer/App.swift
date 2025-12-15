import SwiftUI

@main
struct AFMServerApp: App {
    @StateObject private var serverManager = ServerManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(serverManager)
        } label: {
            Image(systemName: serverManager.isRunning ? "brain.fill" : "brain")
        }
        .menuBarExtraStyle(.window)
    }
}
