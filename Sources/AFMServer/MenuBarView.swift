import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var serverManager: ServerManager
    @Environment(\.openURL) var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("AFM Server")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(serverManager.isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
            }

            Divider()

            // Status info
            VStack(alignment: .leading, spacing: 6) {
                if serverManager.isRunning {
                    HStack {
                        Text("Endpoint:")
                            .foregroundColor(.secondary)
                        Text("http://127.0.0.1:\(serverManager.port)")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                HStack {
                    Text("Model:")
                        .foregroundColor(.secondary)
                    Image(systemName: serverManager.modelAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(serverManager.modelAvailable ? .green : .orange)
                        .font(.caption)
                    Text(serverManager.modelAvailable ? "Available" : "Unavailable")
                }

                if serverManager.requestCount > 0 {
                    HStack {
                        Text("Requests:")
                            .foregroundColor(.secondary)
                        Text("\(serverManager.requestCount)")
                    }
                }
            }
            .font(.callout)

            Divider()

            // Controls
            HStack {
                Button(serverManager.isRunning ? "Stop Server" : "Start Server") {
                    if serverManager.isRunning {
                        serverManager.stop()
                    } else {
                        serverManager.start()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(serverManager.isRunning ? .red : .green)
                .controlSize(.small)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 260)
        .onAppear {
            serverManager.checkModelAvailability()
            serverManager.start()
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(ServerManager())
}
