import CoreGraphics

enum KeyCode {
    static let v: CGKeyCode = 0x09        // kVK_ANSI_V
    static let command: CGKeyCode = 0x37  // kVK_Command
}

enum Limits {
    static let maxHotwords = 100
    /// AES-256 key size in bytes
    static let aes256KeySize = 32
}

enum PanelSize {
    static let width: CGFloat = 360
    static let height: CGFloat = 380
}
