import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    class Coordinator: NSObject, NSWindowDelegate {
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            sender.orderOut(nil)
            return false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.delegate = context.coordinator
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                if window.canBecomeMain {
                    window.makeKeyAndOrderFront(nil)
                    break
                }
            }
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

@main
struct VoiceToTextApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var historyStore = TranscriptionHistoryStore()
    @StateObject private var hotwordsManager = HotwordsManager()

    private static let spinnerFrames = [
        "circle.dotted",
        "circle.dashed",
        "circle.dotted",
        "arrow.triangle.2.circlepath"
    ]

    @State private var spinnerIndex = 0
    @State private var spinnerTimer: Timer?

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(appState)
                .environmentObject(historyStore)
                .environmentObject(hotwordsManager)
                .onAppear {
                    appState.historyStore = historyStore
                    appState.hotwordsManager = hotwordsManager
                }
                .background(WindowAccessor())
        }
        .defaultSize(width: 800, height: 600)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: menuBarIcon)
        }
        .onChange(of: appState.transcriptionPopupText) { newValue in
            if let text = newValue {
                TranscriptionPopupWindowController.shared.show(text: text, appState: appState)
            } else {
                TranscriptionPopupWindowController.shared.hide()
            }
        }
        .onChange(of: appState.isProcessing) { processing in
            if processing {
                startSpinner()
            } else {
                stopSpinner()
            }
        }
    }

    private var menuBarIcon: String {
        if appState.isRecording {
            return "mic.fill"
        } else if appState.isProcessing {
            return Self.spinnerFrames[spinnerIndex % Self.spinnerFrames.count]
        } else {
            return "mic.circle"
        }
    }

    private func startSpinner() {
        spinnerIndex = 0
        spinnerTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            Task { @MainActor in
                spinnerIndex += 1
            }
        }
    }

    private func stopSpinner() {
        spinnerTimer?.invalidate()
        spinnerTimer = nil
        spinnerIndex = 0
    }
}
