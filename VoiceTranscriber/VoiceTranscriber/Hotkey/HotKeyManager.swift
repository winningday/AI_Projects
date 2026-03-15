import Cocoa
import Carbon
import Combine

/// Manages global hotkey registration using Quartz Event Services.
/// Supports configurable hotkey with press-and-hold semantics (press to start, release to stop).
final class HotKeyManager: ObservableObject {
    @Published var isListening = false
    @Published var isCapturingNewHotkey = false

    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?
    var onHotkeyCaptured: ((UInt16, UInt) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var monitoredKeyCode: UInt16
    private var monitoredModifiers: UInt
    private var isKeyDown = false
    /// Use NSEvent-based local/global monitors as a safe fallback
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var flagsMonitor: Any?

    init() {
        let config = ConfigManager.shared
        self.monitoredKeyCode = config.hotkeyKeyCode
        self.monitoredModifiers = config.hotkeyModifiers
    }

    // MARK: - Start/Stop Listening

    func startListening() {
        // Try event tap first; if it fails (no accessibility), use NSEvent monitors
        if AXIsProcessTrusted() {
            startEventTap()
        } else {
            startNSEventMonitors()
        }

        DispatchQueue.main.async {
            self.isListening = true
        }
    }

    private func startEventTap() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                                     (1 << CGEventType.keyUp.rawValue) |
                                     (1 << CGEventType.flagsChanged.rawValue)

        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: context
        ) else {
            print("[HotKeyManager] Event tap failed, falling back to NSEvent monitors")
            startNSEventMonitors()
            return
        }

        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    /// Fallback: use NSEvent monitors (works without full accessibility for modifier keys)
    private func startNSEventMonitors() {
        stopNSEventMonitors()

        // Monitor for flagsChanged (Fn key and modifier keys)
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleNSFlagsChanged(event)
        }

        // Also monitor locally within our app
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            if event.type == .flagsChanged {
                self?.handleNSFlagsChanged(event)
            }
            return event
        }
    }

    private func handleNSFlagsChanged(_ event: NSEvent) {
        // Handle Fn key (keyCode 63)
        if monitoredKeyCode == 63 {
            let fnPressed = event.modifierFlags.contains(.function)

            if fnPressed && !isKeyDown {
                isKeyDown = true
                DispatchQueue.main.async { self.onHotkeyDown?() }
            } else if !fnPressed && isKeyDown {
                isKeyDown = false
                DispatchQueue.main.async { self.onHotkeyUp?() }
            }
        }
    }

    func stopListening() {
        // Stop event tap
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil

        // Stop NSEvent monitors
        stopNSEventMonitors()

        DispatchQueue.main.async {
            self.isListening = false
            self.isKeyDown = false
        }
    }

    private func stopNSEventMonitors() {
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = flagsMonitor { NSEvent.removeMonitor(monitor) }
        globalMonitor = nil
        localMonitor = nil
        flagsMonitor = nil
    }

    // MARK: - Hotkey Configuration

    func updateHotkey(keyCode: UInt16, modifiers: UInt) {
        self.monitoredKeyCode = keyCode
        self.monitoredModifiers = modifiers

        let config = ConfigManager.shared
        config.hotkeyKeyCode = keyCode
        config.hotkeyModifiers = modifiers
    }

    func startCapturingHotkey() {
        isCapturingNewHotkey = true
    }

    func stopCapturingHotkey() {
        isCapturingNewHotkey = false
    }

    // MARK: - Event Tap Handler

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // Handle tap being disabled by system timeout
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        // If we're capturing a new hotkey, intercept the next key press
        if isCapturingNewHotkey && type == .keyDown {
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let modifiers = event.flags.rawValue & (
                CGEventFlags.maskShift.rawValue |
                CGEventFlags.maskControl.rawValue |
                CGEventFlags.maskAlternate.rawValue |
                CGEventFlags.maskCommand.rawValue
            )

            DispatchQueue.main.async {
                self.isCapturingNewHotkey = false
                self.onHotkeyCaptured?(keyCode, UInt(modifiers))
            }

            return nil // Consume the event
        }

        // Handle Fn key specifically (appears as flagsChanged)
        if monitoredKeyCode == 63 && type == .flagsChanged {
            let flags = event.flags
            let fnPressed = flags.contains(.maskSecondaryFn)

            if fnPressed && !isKeyDown {
                isKeyDown = true
                DispatchQueue.main.async { self.onHotkeyDown?() }
                return Unmanaged.passRetained(event) // Don't consume Fn
            } else if !fnPressed && isKeyDown {
                isKeyDown = false
                DispatchQueue.main.async { self.onHotkeyUp?() }
                return Unmanaged.passRetained(event)
            }
            return Unmanaged.passRetained(event)
        }

        // Handle regular key events
        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == monitoredKeyCode else {
            return Unmanaged.passRetained(event)
        }

        // Check modifiers if configured
        if monitoredModifiers != 0 {
            let currentMods = event.flags.rawValue & (
                CGEventFlags.maskShift.rawValue |
                CGEventFlags.maskControl.rawValue |
                CGEventFlags.maskAlternate.rawValue |
                CGEventFlags.maskCommand.rawValue
            )
            guard currentMods == UInt64(monitoredModifiers) else {
                return Unmanaged.passRetained(event)
            }
        }

        if type == .keyDown && !isKeyDown {
            isKeyDown = true
            DispatchQueue.main.async { self.onHotkeyDown?() }
            return nil
        } else if type == .keyUp && isKeyDown {
            isKeyDown = false
            DispatchQueue.main.async { self.onHotkeyUp?() }
            return nil
        }

        return Unmanaged.passRetained(event)
    }

    // MARK: - Accessibility Permission

    func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    // MARK: - Key Name Helpers

    static func keyName(for keyCode: UInt16, modifiers: UInt) -> String {
        var parts: [String] = []

        let mods = UInt64(modifiers)
        if mods & CGEventFlags.maskControl.rawValue != 0 { parts.append("⌃") }
        if mods & CGEventFlags.maskAlternate.rawValue != 0 { parts.append("⌥") }
        if mods & CGEventFlags.maskShift.rawValue != 0 { parts.append("⇧") }
        if mods & CGEventFlags.maskCommand.rawValue != 0 { parts.append("⌘") }

        let keyName: String
        switch keyCode {
        case 63: keyName = "Fn"
        case 36: keyName = "Return"
        case 48: keyName = "Tab"
        case 49: keyName = "Space"
        case 51: keyName = "Delete"
        case 53: keyName = "Escape"
        case 96: keyName = "F5"
        case 97: keyName = "F6"
        case 98: keyName = "F7"
        case 99: keyName = "F3"
        case 100: keyName = "F8"
        case 101: keyName = "F9"
        case 103: keyName = "F11"
        case 105: keyName = "F13"
        case 107: keyName = "F14"
        case 109: keyName = "F10"
        case 111: keyName = "F12"
        case 113: keyName = "F15"
        case 118: keyName = "F4"
        case 120: keyName = "F2"
        case 122: keyName = "F1"
        case 123: keyName = "←"
        case 124: keyName = "→"
        case 125: keyName = "↓"
        case 126: keyName = "↑"
        default:
            if let chars = keyCodeToString(keyCode) {
                keyName = chars.uppercased()
            } else {
                keyName = "Key(\(keyCode))"
            }
        }

        parts.append(keyName)
        return parts.joined()
    }

    private static func keyCodeToString(_ keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        guard let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self)
        let layout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length: Int = 0

        let status = UCKeyTranslate(
            layout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &length,
            &chars
        )

        guard status == noErr && length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
