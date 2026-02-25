# Voice to Text

一个 macOS 原生语音转文字应用，按住 Fn 键即可将语音实时转录为文字并自动输入到当前焦点。

## 功能特性

- **一键录入** — 按住 Fn 键录音，松开后自动转录并输入到当前光标位置
- **智能润色** — 可选接入 Deepseek LLM 对转录文本进行润色、纠错和标点修正
- **热词字典** — 支持自定义热词表（最多 100 个），提升专有名词识别率
- **加密存储** — 所有语音和文字数据使用 AES-256-GCM 加密，仅存储在本地
- **历史记录** — 支持按时间浏览、搜索、回放录音，可配置自动清理策略
- **费用追踪** — 自动记录每次 API 调用的费用

## 技术栈

- Swift 5.10 / SwiftUI
- macOS 13.0+
- [GRDB.swift](https://github.com/groue/GRDB.swift) — SQLite 数据库
- CryptoKit — AES-256-GCM 加密
- Accessibility API — 焦点检测与自动粘贴

## 技术路线

- **Fn 键全局监听** — 使用 [CGEvent Tap](https://developer.apple.com/documentation/coregraphics/cgeventtap) 监听 `flagsChanged`，在独立线程 RunLoop 中运行；仅当 `event.flags.contains(.maskSecondaryFn)` 且无其他修饰键时触发按下/松开，避免与快捷键冲突。实现见 `Services/KeyboardMonitor.swift`，依赖辅助功能权限。
- **焦点是否在输入框** — 使用 [Accessibility API](https://developer.apple.com/documentation/accessibility)：`AXUIElementCreateSystemWide()` → `kAXFocusedApplicationAttribute` → `kAXFocusedUIElementAttribute` 获取当前焦点元素，再根据 `kAXRoleAttribute` 判断是否为 `AXTextField` / `AXTextArea` / `AXComboBox`。实现见 `Services/FocusedInputHelper.swift`。
- **自动输入到焦点** — 若焦点在输入框：先将转录结果写入 `NSPasteboard`，再通过 `CGEvent` 构造并 `post` 模拟 **Cmd+V**，实现「自动粘贴」；否则弹出浮窗供复制。实现见 `Services/ClipboardService.swift`。
- **录音 → 转录 → 润色流水线** — 录音（`AudioRecorderService`）→ 智谱 ASR（`BigModelService`）→ 可选 Deepseek 润色（`DeepseekService`）→ 结果经焦点检测后自动输入或弹窗。流水线见 `Services/SpeechProcessor.swift` 与 `AppState.swift`。

## API 依赖

| 服务 | 用途 | 必需 |
|------|------|------|
| [智谱 BigModel](https://open.bigmodel.cn/) | 语音转文字 (GLM-ASR-2512) | 是 |
| [Deepseek](https://platform.deepseek.com/) | 文本润色 (deepseek-chat) | 否 |

## 下载

在 [GitHub Releases](https://github.com/SherlockShemol/voice-to-text/releases) 选择最新版本，下载 **VoiceToText-macOS.dmg**，打开后将 **Voice to Text.app** 拖入「应用程序」即可。首次运行需在 **系统设置 → 隐私与安全性** 中授予 **麦克风** 与 **辅助功能** 权限。新版本通过 push 版本 tag 自动发布带 .dmg 的 Release。

## 构建与运行

**方式一：Swift Package Manager**

```bash
# 克隆仓库
git clone https://github.com/SherlockShemol/voice-to-text.git
cd voice-to-text

# 构建
swift build

# 运行
swift run
```

**方式二：Xcode（可打包为 .app）**

使用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 生成工程后归档导出：

```bash
brew install xcodegen
xcodegen generate
open VoiceToText.xcodeproj
# 在 Xcode 中 Product → Archive → Distribute App
```

## 权限要求

应用需要以下系统权限：

1. **麦克风权限** — 用于录制语音
2. **辅助功能权限** — 用于检测焦点输入框并模拟粘贴

## 使用方法

1. 启动应用后，在设置页面配置 BigModel API 密钥（必需）和 Deepseek API 密钥（可选）
2. 授予麦克风和辅助功能权限
3. 按住 Fn 键开始录音，松开后自动转录
4. 如果焦点在输入框中，文本会自动填入；否则会弹出浮窗供复制

## 项目结构

```
Sources/VoiceToText/
├── VoiceToTextApp.swift          # 应用入口
├── AppState.swift                # 应用状态管理
├── Views/
│   ├── MainWindowView.swift      # 主窗口（侧边栏导航）
│   ├── HomeView.swift            # 首页（状态仪表盘）
│   ├── HistoryView.swift         # 历史记录
│   ├── HotwordsView.swift        # 热词字典
│   ├── SettingsView.swift        # 设置页
│   ├── MenuBarView.swift         # 菜单栏
│   └── TranscriptionPopupView.swift  # 转录结果浮窗
└── Services/
    ├── SpeechProcessor.swift     # 转录+润色流水线
    ├── BigModelService.swift     # 智谱语音识别 API
    ├── DeepseekService.swift     # Deepseek 润色 API
    ├── AudioRecorderService.swift # 音频录制
    ├── TranscriptionHistory.swift # 历史记录存储
    ├── DatabaseService.swift     # SQLite 数据库
    ├── EncryptionService.swift   # AES-256-GCM 加密
    ├── KeychainManager.swift     # Keychain 密钥管理
    ├── KeyboardMonitor.swift     # Fn 键监听
    └── FocusedInputHelper.swift  # 焦点检测与粘贴
```

## 许可证

[MIT License](LICENSE)
