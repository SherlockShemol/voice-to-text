import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuButton("打开 Voice to Text 主页") {
                showMainWindow()
            }

            Divider()

            menuButton("设置...", shortcut: "⌘,") {
                showMainWindow()
            }

            Divider()

            if appState.isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                    Text("正在录音...")
                        .font(.subheadline)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            } else if let stage = appState.processingStage {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(stage == .transcribing ? "正在转录..." : "正在润色...")
                        .font(.subheadline)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            Divider()

            Text("版本 0.0.1")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            Divider()

            menuButton("退出 Voice to Text", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 4)
        .frame(width: 220)
    }

    // MARK: - Menu Button

    private func menuButton(_ title: String, shortcut: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "Voice to Text" || $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            for window in NSApp.windows where !window.title.isEmpty && window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
    }
}
