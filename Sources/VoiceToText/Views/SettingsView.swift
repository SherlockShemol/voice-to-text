import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var historyStore: TranscriptionHistoryStore
    @State private var showSavedToast = false
    @State private var editingBigModelKey = ""
    @State private var editingDeepseekKey = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("设置")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                settingsForm
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if showSavedToast {
                Text("已保存")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.green.opacity(0.9))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showSavedToast)
        .onAppear {
            editingBigModelKey = appState.bigModelAPIKey
            editingDeepseekKey = appState.deepseekAPIKey
        }
    }

    private var settingsForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection(
                title: "BigModel 语音转文字",
                icon: "waveform",
                description: "智谱 GLM-ASR-2512 语音识别接口密钥"
            ) {
                SecureField("BigModel API Key", text: $editingBigModelKey)
                    .textFieldStyle(.roundedBorder)
            }

            settingsSection(
                title: "Deepseek 文本润色",
                icon: "key",
                description: "用于文本润色的 Deepseek LLM 接口密钥（可选）"
            ) {
                SecureField("Deepseek API Key", text: $editingDeepseekKey)
                    .textFieldStyle(.roundedBorder)
            }

            settingsSection(
                title: "数据与存储",
                icon: "lock.shield",
                description: "语音和文字数据使用 AES-256-GCM 加密存储在本地数据库中"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("保存录音文件", isOn: Binding(
                        get: { appState.saveAudioEnabled },
                        set: { appState.setSaveAudio($0) }
                    ))
                    .toggleStyle(.switch)

                    Text("开启后，录音音频将加密保存，可在历史记录中回放")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()

                    HStack {
                        Label("数据库大小", systemImage: "internaldrive")
                            .font(.subheadline)
                        Spacer()
                        Text(formatBytes(historyStore.databaseFileSize))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }

            HStack {
                Spacer()
                Button("保存") {
                    appState.saveAPIKeys(bigModel: editingBigModelKey, deepseek: editingDeepseekKey)
                    showSavedToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showSavedToast = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        icon: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
            content()
        }
        .padding(16)
        .background(.quaternary.opacity(0.5))
        .cornerRadius(8)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
