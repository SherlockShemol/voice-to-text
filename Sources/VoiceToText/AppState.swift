import SwiftUI
import AVFoundation
import AppKit

@MainActor
final class AppState: ObservableObject {

    private(set) var deepseekAPIKey: String = ""
    private(set) var bigModelAPIKey: String = ""
    private(set) var polishPrompt: String = ""
    @Published var microphonePermissionGranted: Bool = false
    @Published var isRecording: Bool = false
    @Published var processingStage: ProcessingStage? = nil
    @Published var accessibilityPermissionGranted: Bool = false
    @Published var saveAudioEnabled: Bool = true
    /// 非 nil 时显示转录结果浮窗（未在输入框时）；弹窗内仅点击复制才写入剪贴板。
    @Published var transcriptionPopupText: String?
    @Published var lastError: String?

    var historyStore: TranscriptionHistoryStore?
    var hotwordsManager: HotwordsManager?

    var isProcessing: Bool { processingStage != nil }

    private let promptFileName = "polish_prompt"
    private let saveAudioKey = "saveAudioEnabled"
    private var keyboardMonitor: KeyboardMonitor?
    private let audioRecorder = AudioRecorderService()
    private var currentRecordingURL: URL?

    init() {
        loadAPIKeys()
        loadPrompt()
        loadPreferences()
        checkMicrophonePermission()
        checkAccessibilityPermission()
        setupKeyboardMonitor()
    }

    // MARK: - API Key Storage (via KeychainManager)

    func loadAPIKeys() {
        deepseekAPIKey = KeychainManager.deepseekAPIKey ?? ""
        bigModelAPIKey = KeychainManager.bigModelAPIKey ?? ""
    }

    func saveAPIKeys(bigModel: String, deepseek: String) {
        bigModelAPIKey = bigModel
        deepseekAPIKey = deepseek
        KeychainManager.bigModelAPIKey = bigModel
        KeychainManager.deepseekAPIKey = deepseek
    }

    // MARK: - Preferences

    private func loadPreferences() {
        if UserDefaults.standard.object(forKey: saveAudioKey) != nil {
            saveAudioEnabled = UserDefaults.standard.bool(forKey: saveAudioKey)
        }
    }

    func setSaveAudio(_ enabled: Bool) {
        saveAudioEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: saveAudioKey)
    }

    // MARK: - Prompt

    private var projectRootURL: URL? {
        guard var url = Bundle.main.executableURL else { return nil }
        while url.path != "/" {
            url = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
        }
        return nil
    }

    private var promptFileURL: URL? {
        // 1) .app 打包：资源在 App Bundle 的 Contents/Resources
        if let inBundle = Bundle.main.url(forResource: "polish_prompt", withExtension: nil) {
            return inBundle
        }
        // 2) 开发时从仓库根目录运行（如 swift run）
        if let projectRoot = projectRootURL {
            let projectFile = projectRoot
                .appendingPathComponent("Sources/VoiceToText/Resources")
                .appendingPathComponent(promptFileName)
            if FileManager.default.fileExists(atPath: projectFile.path) {
                return projectFile
            }
        }
        // 3) SPM 构建（如 swift run）：仅在 SPM 环境下使用 Bundle.module，Xcode App 构建时无此 API
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: "polish_prompt", withExtension: nil)
        #else
        return nil
        #endif
    }

    private func loadPrompt() {
        guard let url = promptFileURL,
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            print("[AppState] Prompt file not found")
            polishPrompt = ""
            return
        }
        polishPrompt = contents
    }


    // MARK: - Permissions

    func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphonePermissionGranted = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    self?.microphonePermissionGranted = granted
                }
            }
        default:
            microphonePermissionGranted = false
        }
    }

    // MARK: - Accessibility Permission

    func checkAccessibilityPermission() {
        accessibilityPermissionGranted = AXIsProcessTrusted()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func recheckAccessibilityAndRestartMonitor() {
        checkAccessibilityPermission()
        keyboardMonitor?.stop()
        keyboardMonitor?.start()
    }

    // MARK: - Keyboard Monitor

    private func setupKeyboardMonitor() {
        let monitor = KeyboardMonitor()
        monitor.onFnKeyDown = { [weak self] in
            Task { @MainActor in
                self?.startRecording()
            }
        }
        monitor.onFnKeyUp = { [weak self] in
            Task { @MainActor in
                self?.stopRecording()
            }
        }
        keyboardMonitor = monitor
        monitor.start()
    }

    // MARK: - Recording

    func startRecording() {
        guard !isRecording else { return }
        guard microphonePermissionGranted else {
            lastError = "麦克风权限未授权"
            return
        }

        if let url = audioRecorder.startRecording() {
            currentRecordingURL = url
            isRecording = true
        } else {
            lastError = "录音启动失败"
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        guard let url = audioRecorder.stopRecording() else { return }
        print("[AppState] Recording stopped: \(url.lastPathComponent)")

        Task {
            await transcribeRecording(fileURL: url)
        }
    }

    private func transcribeRecording(fileURL: URL) async {
        guard !bigModelAPIKey.isEmpty else {
            lastError = "BigModel API 密钥未配置"
            audioRecorder.cleanup(url: fileURL)
            return
        }

        defer {
            processingStage = nil
            audioRecorder.cleanup(url: fileURL)
        }

        let audioData: Data? = saveAudioEnabled ? try? Data(contentsOf: fileURL) : nil

        let processor = SpeechProcessor(
            bigModelAPIKey: bigModelAPIKey,
            deepseekAPIKey: deepseekAPIKey,
            polishPrompt: polishPrompt,
            hotwords: hotwordsManager?.hotwords ?? []
        )
        processor.onStageChange = { [weak self] stage in
            Task { @MainActor in
                self?.processingStage = stage
            }
        }

        do {
            let result = try await processor.process(audioFileURL: fileURL)
            if FocusedInputHelper.isFocusedElementTextInput() {
                ClipboardService.pasteToFocused(result.refinedText)
            } else {
                transcriptionPopupText = result.refinedText
            }
            historyStore?.addRecord(
                rawText: result.rawText,
                refinedText: result.refinedText,
                didUseRefinement: !result.didFallback && !deepseekAPIKey.isEmpty,
                transcriptionMeta: result.transcriptionMeta,
                refinementMeta: result.refinementMeta,
                audioData: audioData
            )
        } catch {
            lastError = "转录失败：\(error.localizedDescription)"
        }
    }

    func copyToClipboard(_ text: String) {
        ClipboardService.copy(text)
    }

    func dismissTranscriptionPopup() {
        transcriptionPopupText = nil
    }

    // MARK: - Status Helpers

    var isDeepseekConfigured: Bool {
        !deepseekAPIKey.isEmpty
    }

    var isBigModelConfigured: Bool {
        !bigModelAPIKey.isEmpty
    }

    var isFullyConfigured: Bool {
        isDeepseekConfigured && isBigModelConfigured && !polishPrompt.isEmpty
    }
}
