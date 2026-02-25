import Foundation
import AppKit
import ApplicationServices

/// 使用无障碍 API 检测当前焦点是否为输入框。
enum FocusedInputHelper {

    /// 当前焦点是否在可编辑文本控件内（无辅助功能权限时返回 false，走弹窗逻辑）。
    static func isFocusedElementTextInput() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard let focused = getFocusedUIElement() else { return false }
        return isTextInputElement(focused)
    }

    // MARK: - Private

    private static func getFocusedUIElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var appRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &appRef) == .success,
              let app = appRef else { return nil }
        // swiftlint:disable:next force_cast — AXUIElement is a CFTypeRef alias, conditional cast is not possible
        let appElement = app as! AXUIElement
        var elementRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &elementRef) == .success,
              let element = elementRef else { return nil }
        // swiftlint:disable:next force_cast
        return (element as! AXUIElement)
    }

    private static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]

    private static func isTextInputElement(_ element: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else { return false }
        return textRoles.contains(role)
    }
}
