import Carbon
import CoreGraphics
import Foundation

nonisolated struct Shortcut: Codable, Equatable {
    static let modifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
    static let keyboard = Self(keyCode: Int64(kVK_ANSI_K), flags: [.maskControl, .maskShift], key: "K")
    static let pointer = Self(keyCode: Int64(kVK_ANSI_P), flags: [.maskControl, .maskShift], key: "P")
    static let lock = Self(keyCode: Int64(kVK_ANSI_A), flags: [.maskControl, .maskShift], key: "A")
    static let unlock = Self(keyCode: Int64(kVK_Escape), flags: [.maskControl, .maskShift], key: "Esc")

    let keyCode: Int64
    let modifierFlags: UInt64
    let key: String

    init(keyCode: Int64, flags: CGEventFlags, key: String) {
        self.keyCode = keyCode
        modifierFlags = flags.intersection(Self.modifiers).rawValue
        self.key = key
    }

    var label: String {
        let flags = CGEventFlags(rawValue: modifierFlags)
        let symbols: [(CGEventFlags, String)] = [
            (.maskControl, "⌃"), (.maskAlternate, "⌥"), (.maskShift, "⇧"), (.maskCommand, "⌘"),
        ]
        return symbols.filter { flags.contains($0.0) }.map(\.1).joined() + localizedKey
    }

    private var localizedKey: String {
        switch Int(keyCode) {
        case kVK_Escape: return String(localized: "Esc")
        case kVK_Space: return String(localized: "Space")
        case kVK_Tab: return "Tab"
        case kVK_Return: return String(localized: "Return")
        case kVK_Delete: return "⌫"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            if key.isEmpty || key == "Touche \(keyCode)" {
                return String(localized: "Key \(keyCode)")
            }
            return key
        }
    }

    func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        self.keyCode == keyCode && modifierFlags == flags.intersection(Self.modifiers).rawValue
    }

    static func lockForCurrentLayout() -> Self {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData),
              let bytes = CFDataGetBytePtr(Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue())
        else { return .lock }

        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        let keyboardType = UInt32(LMGetKbdType())
        for code in UInt16(0)...127 {
            var state: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, code, UInt16(kUCKeyActionDisplay), 0, keyboardType,
                OptionBits(kUCKeyTranslateNoDeadKeysMask), &state, characters.count, &length, &characters
            )
            if status == noErr, length == 1, characters[0] == 65 || characters[0] == 97 {
                return Self(keyCode: Int64(code), flags: [.maskControl, .maskShift], key: "A")
            }
        }
        return .lock
    }
}

nonisolated struct InputFilter {
    enum Action {
        case toggleKeyboard
        case togglePointer
        case lockAll
        case unlockAll
    }

    enum Decision {
        case pass
        case discard
        case freeze(CGPoint)
        case perform(Action)
        case detectPaws(PawPattern)
    }

    static let keyboardEvents: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
    static let movements: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
    static let buttonDowns: [CGEventType] = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    static let buttonUps: [CGEventType] = [.leftMouseUp, .rightMouseUp, .otherMouseUp]
    static let pointerEvents = movements + buttonDowns + buttonUps + [.scrollWheel]
    static let intentionalPointerEvents = buttonDowns + [.leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]

    var keyboardShortcut = Shortcut.keyboard
    var pointerShortcut = Shortcut.pointer
    var lockShortcut = Shortcut.lock
    private(set) var keyboardLocked = false
    var pointerAnchor: CGPoint?
    var recordingShortcut = false {
        didSet { if recordingShortcut { paws.pause() } }
    }
    var automaticLockEnabled = false {
        didSet { if automaticLockEnabled != oldValue { resetPawDetection() } }
    }
    var automaticLockRules = AutomaticLockRules() {
        didSet { if automaticLockRules != oldValue { resetPawDetection() } }
    }
    private(set) var keyboardActivity: KeyboardActivity?

    private var discardedKeys = Set<Int64>()
    private var quietRepeats = Set<Int64>()
    private var discardedButtons = Set<Int64>()
    private var visibleModifiers = CGEventFlags()
    private var paws = PawDetector()

    var pawHoldDeadline: UInt64? {
        guard automaticLockEnabled, !recordingShortcut, !keyboardLocked else { return nil }
        return paws.pendingHold?.deadline
    }

    func detectHeldPaws(at time: UInt64) -> PawPattern? {
        guard automaticLockEnabled, !recordingShortcut, !keyboardLocked,
              let hold = paws.pendingHold, time >= hold.deadline else { return nil }
        return hold.pattern
    }

    mutating func beginKeyboardLock(at time: UInt64, automatically: Bool = false, suppressing key: Int64? = nil) {
        keyboardLocked = true
        keyboardActivity = KeyboardActivity(startedAt: time)
        if automatically {
            for heldKey in paws.heldKeys {
                // Count the portion of an existing press that occurs while the keyboard is locked.
                keyboardActivity?.press(heldKey, at: time)
                quietRepeats.insert(heldKey)
            }
            if let key { discardedKeys.insert(key) }
        }
        paws.pause()
    }

    mutating func endKeyboardLock() {
        keyboardLocked = false
        paws.pause()
    }

    mutating func finishKeyboardActivity(at time: UInt64) -> KeyboardSession? {
        guard var activity = keyboardActivity else { return nil }
        keyboardActivity = nil
        return activity.finish(at: time)
    }

    mutating func resetPawDetection() {
        var rules = automaticLockRules
        rules.clampThresholds()
        paws = PawDetector(rules: rules)
    }

    mutating func handle(_ type: CGEventType, event: CGEvent) -> Decision {
        if automaticLockEnabled && Self.intentionalPointerEvents.contains(type) { paws.cancelSingleKeyHold() }
        switch type {
        case .keyDown, .keyUp:
            return handleKey(type, event: event)
        case .flagsChanged:
            paws.cancelSingleKeyHold()
            keyboardActivity?.updateModifier(
                event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags, at: event.timestamp
            )
            let flags = event.flags.intersection(Shortcut.modifiers)
            if !flags.isEmpty { paws.pause() }
            if !keyboardLocked {
                visibleModifiers = flags
                return .pass
            }
            // Let go of modifiers whose press reached another app before locking.
            let remaining = visibleModifiers.intersection(flags)
            guard remaining != visibleModifiers else { return .discard }
            visibleModifiers = remaining
            event.flags = event.flags.subtracting(Shortcut.modifiers).union(remaining)
            return .pass
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard pointerAnchor != nil else { return .pass }
            discardedButtons.insert(event.getIntegerValueField(.mouseEventButtonNumber))
            return .discard
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            return discardedButtons.remove(button) != nil ? .discard : .pass
        default:
            guard let pointerAnchor else { return .pass }
            if Self.movements.contains(type) { return .freeze(pointerAnchor) }
            return type == .scrollWheel ? .discard : .pass
        }
    }

    private mutating func handleKey(_ type: CGEventType, event: CGEvent) -> Decision {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let detecting = !keyboardLocked && !recordingShortcut && flags.intersection(Shortcut.modifiers).isEmpty
        if type == .keyUp {
            keyboardActivity?.release(keyCode, at: event.timestamp)
            quietRepeats.remove(keyCode)
            let discarded = discardedKeys.remove(keyCode) != nil
            if automaticLockEnabled, let pattern = paws.release(keyCode, at: event.timestamp, detecting: detecting) {
                return .detectPaws(pattern)
            }
            return discarded ? .discard : .pass
        }

        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if isRepeat {
            return keyboardLocked || discardedKeys.contains(keyCode) || quietRepeats.contains(keyCode) ? .discard : .pass
        }
        // A fresh physical press can follow a release we missed during secure input.
        discardedKeys.remove(keyCode)
        quietRepeats.remove(keyCode)
        if let action = shortcutAction(keyCode: keyCode, flags: flags) {
            paws.pause()
            keyboardActivity?.excludeShortcutModifiers()
            discardedKeys.insert(keyCode)
            return .perform(action)
        }
        if automaticLockEnabled, let pattern = paws.press(keyCode, at: event.timestamp, detecting: detecting) {
            return .detectPaws(pattern)
        }
        guard keyboardLocked else { return .pass }
        keyboardActivity?.press(keyCode, at: event.timestamp)
        discardedKeys.insert(keyCode)
        return .discard
    }

    private func shortcutAction(keyCode: Int64, flags: CGEventFlags) -> Action? {
        if Shortcut.unlock.matches(keyCode: keyCode, flags: flags) { return .unlockAll }
        if recordingShortcut { return nil }
        if keyboardShortcut.matches(keyCode: keyCode, flags: flags) { return .toggleKeyboard }
        if pointerShortcut.matches(keyCode: keyCode, flags: flags) { return .togglePointer }
        if lockShortcut.matches(keyCode: keyCode, flags: flags) { return .lockAll }
        return nil
    }
}
