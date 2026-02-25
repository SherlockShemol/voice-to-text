import SwiftUI
import AppKit

/// 用于 NSPanel 的固定类型根视图（便于更新 rootView）。
private struct TranscriptionPopupContent: View {
    let text: String
    @ObservedObject var appState: AppState
    var body: some View {
        TranscriptionPopupView(text: text).environmentObject(appState)
    }
}

/// 屏幕中下位置的转录结果浮窗，使用 NSPanel。
final class TranscriptionPopupWindowController {

    static let shared = TranscriptionPopupWindowController()

    private var panel: NSPanel?
    private var hostingController: NSHostingController<TranscriptionPopupContent>?

    private init() {}

    func show(text: String, appState: AppState) {
        if panel == nil {
            setupPanel(appState: appState)
        }
        hostingController?.rootView = TranscriptionPopupContent(text: text, appState: appState)
        guard let panel = panel else { return }
        positionPanel(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func setupPanel(appState: AppState) {
        let content = TranscriptionPopupContent(text: "", appState: appState)
        let hosting = NSHostingController(rootView: content)
        hostingController = hosting

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: PanelSize.width, height: PanelSize.height),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentViewController = hosting
        panel.isMovableByWindowBackground = true
        self.panel = panel
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame
        let x = screenFrame.midX - panelFrame.width / 2
        let y = screenFrame.minY + screenFrame.height * 0.35 - panelFrame.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
