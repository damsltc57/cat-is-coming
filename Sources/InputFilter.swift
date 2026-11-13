import Carbon
import CoreGraphics
import Foundation

nonisolated struct Shortcut: Codable, Equatable {
    static let modifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
    static let keyboard = Self(keyCode: Int64(kVK_ANSI_K), flags: [.maskControl, .maskShift], key: "K")
    static let pointer = Self(keyCode: Int64(kVK_ANSI_P), flags: [.maskControl, .maskShift], key: "P")
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
}

nonisolated struct InputFilter {
    enum Action {
        case toggleKeyboard
        case togglePointer
        case unlockAll
    }

    enum Decision {
        case pass
        case discard
        case freeze(CGPoint)
        case perform(Action)
    }

    static let keyboardEvents: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
    static let movements: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
    static let buttonDowns: [CGEventType] = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    static let buttonUps: [CGEventType] = [.leftMouseUp, .rightMouseUp, .otherMouseUp]
    static let pointerEvents = movements + buttonDowns + buttonUps + [.scrollWheel]

    var keyboardShortcut = Shortcut.keyboard
    var pointerShortcut = Shortcut.pointer
    var keyboardLocked = false
    var pointerAnchor: CGPoint?
    var recordingShortcut = false
    var keyboardActivity: KeyboardActivity?

    private var discardedKeys = Set<Int64>()
    private var discardedButtons = Set<Int64>()
    private var visibleModifiers = CGEventFlags()

    mutating func handle(_ type: CGEventType, event: CGEvent) -> Decision {
        switch type {
        case .keyDown, .keyUp:
            return handleKey(type, event: event)
        case .flagsChanged:
            keyboardActivity?.updateModifier(
                event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags, at: event.timestamp
            )
            let flags = event.flags.intersection(Shortcut.modifiers)
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
        if type == .keyUp {
            keyboardActivity?.release(keyCode, at: event.timestamp)
            return discardedKeys.remove(keyCode) != nil ? .discard : .pass
        }
        if discardedKeys.contains(keyCode) { return .discard }

        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let flags = event.flags
        if !isRepeat, let action = shortcutAction(keyCode: keyCode, flags: flags) {
            keyboardActivity?.excludeShortcutModifiers()
            discardedKeys.insert(keyCode)
            return .perform(action)
        }
        guard keyboardLocked else { return .pass }
        if !isRepeat {
            keyboardActivity?.press(keyCode, at: event.timestamp)
            discardedKeys.insert(keyCode)
        }
        return .discard
    }

    private func shortcutAction(keyCode: Int64, flags: CGEventFlags) -> Action? {
        if Shortcut.unlock.matches(keyCode: keyCode, flags: flags) { return .unlockAll }
        if recordingShortcut { return nil }
        if keyboardShortcut.matches(keyCode: keyCode, flags: flags) { return .toggleKeyboard }
        if pointerShortcut.matches(keyCode: keyCode, flags: flags) { return .togglePointer }
        return nil
    }
}
