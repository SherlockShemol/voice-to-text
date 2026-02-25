import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                statusSection
                errorBanner
                recordingStatusSection
                usageSection
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Voice to Text")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("按住 Fn 键，说话即输入")
                .font(.title3)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("状态")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                statusCard(
                    title: "麦克风权限",
                    isOK: appState.microphonePermissionGranted,
                    icon: "mic.fill"
                )
                statusCard(
                    title: "辅助功能权限",
                    isOK: appState.accessibilityPermissionGranted,
                    icon: "hand.raised.fill"
                )
                statusCard(
                    title: "BigModel API",
                    isOK: appState.isBigModelConfigured,
                    icon: "waveform"
                )
                statusCard(
                    title: "Deepseek API",
                    isOK: appState.isDeepseekConfigured,
                    icon: "text.badge.star"
                )
            }

            if !appState.accessibilityPermissionGranted {
                HStack(spacing: 12) {
                    Button("打开辅助功能设置") {
                        appState.openAccessibilitySettings()
                    }
                    Button("重新检查权限") {
                        appState.recheckAccessibilityAndRestartMonitor()
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.top, 4)
            }
        }
    }

    private func statusCard(title: String, isOK: Bool, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(isOK ? .green : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(isOK ? "已就绪" : "未配置")
                    .font(.caption)
                    .foregroundColor(isOK ? .green : .red)
            }
            Spacer()
            Image(systemName: isOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isOK ? .green : .red)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Error Banner

    @ViewBuilder
    private var errorBanner: some View {
        if let error = appState.lastError {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(error)
                    .font(.subheadline)
                Spacer()
                Button {
                    appState.lastError = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(.orange.opacity(0.1))
            .cornerRadius(8)
        }
    }

    // MARK: - Recording Status

    private var recordingStatusSection: some View {
        Group {
            if appState.isRecording {
                HStack(spacing: 12) {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                    Text("正在录音...")
                        .font(.headline)
                        .foregroundColor(.red)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.red.opacity(0.1))
                .cornerRadius(8)
            } else if let stage = appState.processingStage {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text(stage == .transcribing ? "正在转录..." : "正在润色...")
                        .font(.headline)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Usage

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("使用说明")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                usageRow(step: "1", text: "确保麦克风和辅助功能权限已授权")
                usageRow(step: "2", text: "配置 BigModel API 密钥（必需）和 Deepseek API 密钥（可选）")
                usageRow(step: "3", text: "按住 Fn 键开始语音录入，松开后自动转录")
                usageRow(step: "4", text: "焦点在输入框时自动填入，否则在屏幕中下弹窗显示，点击「复制」后写入剪贴板")
            }
            .padding(16)
            .background(.quaternary.opacity(0.5))
            .cornerRadius(8)
        }
    }

    private func usageRow(step: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(step)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(.blue)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}
