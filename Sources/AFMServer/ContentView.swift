import SwiftUI

struct ContentView: View {
    @EnvironmentObject var serverManager: ServerManager

    var body: some View {
        VStack(spacing: 16) {
            // Status indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(serverManager.isRunning ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                Text(serverManager.isRunning ? "Server Running" : "Server Stopped")
                    .font(.headline)
            }

            // Server info
            if serverManager.isRunning {
                Text("http://127.0.0.1:\(serverManager.port)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            // Model status
            HStack(spacing: 8) {
                Image(systemName: serverManager.modelAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(serverManager.modelAvailable ? .green : .orange)
                Text(serverManager.modelAvailable ? "Model Available" : "Model Unavailable")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Control buttons
            HStack(spacing: 12) {
                Button(serverManager.isRunning ? "Stop" : "Start") {
                    if serverManager.isRunning {
                        serverManager.stop()
                    } else {
                        serverManager.start()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(serverManager.isRunning ? .red : .green)
            }

            // Request count
            if serverManager.requestCount > 0 {
                Text("Requests: \(serverManager.requestCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(24)
        .frame(minWidth: 280)
        .onAppear {
            serverManager.checkModelAvailability()
            serverManager.start()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ServerManager())
}
