import Cocoa
import Carbon

/// Injects text into the currently focused text field of the active application.
/// Uses the macOS Accessibility API with a pasteboard fallback.
final class TextInjector {

    enum InjectionMethod {
        case accessibility  // Preferred: uses AX API to set value directly
        case pasteboard     // Fallback: copies to clipboard and simulates Cmd+V
    }

    /// Injects the given text into the currently active text field.
    /// Tries accessibility API first, falls back to pasteboard-based injection.
    static func inject(text: String) {
        // Try accessibility-based injection first
        if injectViaAccessibility(text: text) {
            return
        }

        // Fallback to pasteboard
        injectViaPasteboard(text: text)
    }

    // MARK: - Accessibility-Based Injection

    private static func injectViaAccessibility(text: String) -> Bool {
        guard let focusedApp = NSWorkspace.shared.frontmostApplication else { return false }

        let appElement = AXUIElementCreateApplication(focusedApp.processIdentifier)

        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard result == .success else { return false }

        let element = focusedElement as! AXUIElement

        // Check if the element accepts text input
        var role: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)

        // Try to set the value directly
        let setResult = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)

        if setResult == .success {
            return true
        }

        // If direct value setting fails, try inserting at selection
        var selectedRange: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange)

        if rangeResult == .success {
            let insertResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
            return insertResult == .success
        }

        return false
    }

    // MARK: - Pasteboard-Based Injection

    private static func injectViaPasteboard(text: String) {
        // Save current clipboard contents
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        // Set text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure pasteboard is ready
        usleep(50_000) // 50ms

        // Simulate Cmd+V
        simulateKeyPress(keyCode: 9, flags: .maskCommand) // 'V' key

        // Restore previous clipboard after a delay
        if let previous = previousContents {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }

    // MARK: - Key Simulation

    private static func simulateKeyPress(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = flags
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = flags
        keyUp?.post(tap: .cghidEventTap)
    }
}
