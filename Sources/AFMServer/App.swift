import SwiftUI

@main
struct AFMServerApp: App {
    @StateObject private var serverManager = ServerManager()

    init() {
        // Start server immediately on app launch
        DispatchQueue.main.async {
            ServerManager.shared.checkModelAvailability()
            ServerManager.shared.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(ServerManager.shared)
        } label: {
            Image(systemName: ServerManager.shared.isRunning ? "brain.fill" : "brain")
        }
        .menuBarExtraStyle(.window)
    }
}
