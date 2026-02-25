import AppKit

enum ClipboardService {

    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Writes text to clipboard and simulates Cmd+V to paste into the focused field.
    static func pasteToFocused(_ text: String) {
        copy(text)
        simulateCmdV()
    }

    private static func simulateCmdV() {
        let loc = CGEventTapLocation.cghidEventTap

        guard let cmdDown = CGEvent(keyboardEventSource: nil, virtualKey: KeyCode.command, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: nil, virtualKey: KeyCode.v, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: nil, virtualKey: KeyCode.v, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: nil, virtualKey: KeyCode.command, keyDown: false) else { return }

        vDown.flags = .maskCommand
        vUp.flags = .maskCommand

        cmdDown.post(tap: loc)
        vDown.post(tap: loc)
        vUp.post(tap: loc)
        cmdUp.post(tap: loc)
    }
}
