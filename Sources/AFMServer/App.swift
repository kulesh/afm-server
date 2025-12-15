import SwiftUI

@main
struct AFMServerApp: App {
    @StateObject private var serverManager = ServerManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(serverManager)
        }
        .windowResizability(.contentSize)
    }
}
