import Cocoa
import Carbon

/// Injects text into the currently focused text field of the active application.
/// Always APPENDS at the current cursor position — never replaces existing content.
final class TextInjector {

    /// Injects the given text at the current cursor position in the active text field.
    /// Uses pasteboard + Cmd+V which naturally inserts at cursor without replacing.
    static func inject(text: String) {
        // Always use pasteboard method — it reliably inserts at cursor
        // without replacing existing content (unless user has a text selection,
        // which is expected paste behavior)
        injectViaPasteboard(text: text)
    }

    // MARK: - Pasteboard-Based Injection

    private static func injectViaPasteboard(text: String) {
        let pasteboard = NSPasteboard.general

        // Save current clipboard contents
        let previousContents = pasteboard.string(forType: .string)

        // Set our text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure pasteboard is ready
        usleep(50_000) // 50ms

        // Simulate Cmd+V to paste at cursor position
        simulateKeyPress(keyCode: 9, flags: .maskCommand) // 'V' key

        // Restore previous clipboard after a delay
        if let previous = previousContents {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }

    // MARK: - Context Reading (for context-aware transcription)

    /// Reads surrounding text from the currently focused text field.
    /// Used to provide context to the LLM for better transcription accuracy.
    static func readContextFromActiveField() -> String? {
        guard let focusedApp = NSWorkspace.shared.frontmostApplication else { return nil }

        let appElement = AXUIElementCreateApplication(focusedApp.processIdentifier)

        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard result == .success else { return nil }

        let element = focusedElement as! AXUIElement

        // Try to read current text value
        var value: AnyObject?
        let valueResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)

        if valueResult == .success, let text = value as? String {
            // Return last ~200 chars for context
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 200 {
                return String(trimmed.suffix(200))
            }
            return trimmed.isEmpty ? nil : trimmed
        }

        return nil
    }

    /// Returns the name of the currently focused application.
    static func activeAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
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
