import Carbon
import CoreGraphics
import IOKit.hidsystem

nonisolated struct KeyActivity {
    var presses = 0
    var heldNanoseconds: UInt64 = 0

    var heldSeconds: Double { Double(heldNanoseconds) / 1_000_000_000 }
}

nonisolated struct KeyboardSession {
    let keys: [Int64: KeyActivity]
    let duration: Duration
}

nonisolated struct KeyboardActivity {
    private let startedAt: UInt64
    private(set) var keys: [Int64: KeyActivity] = [:]
    private var heldSince: [Int64: UInt64] = [:]

    init(startedAt: UInt64) {
        self.startedAt = startedAt
    }

    mutating func press(_ key: Int64, at time: UInt64) {
        guard heldSince[key] == nil else { return }
        keys[key, default: KeyActivity()].presses += 1
        heldSince[key] = time
    }

    mutating func release(_ key: Int64, at time: UInt64) {
        guard let start = heldSince.removeValue(forKey: key), time >= start else { return }
        keys[key, default: KeyActivity()].heldNanoseconds += time - start
    }

    mutating func updateModifier(_ key: Int64, flags: CGEventFlags, at time: UInt64) {
        if key == kVK_CapsLock {
            // Caps Lock reports a toggle, so its physical hold time is unavailable.
            keys[key, default: KeyActivity()].presses += 1
            return
        }
        guard let mask = Self.modifierMask(for: key) else { return }
        if flags.rawValue & mask != 0 {
            press(key, at: time)
        } else {
            release(key, at: time)
        }
    }

    mutating func excludeShortcutModifiers() {
        for key in heldSince.keys.filter({ Self.isShortcutModifier($0) }) {
            heldSince.removeValue(forKey: key)
            keys[key]?.presses -= 1
            if keys[key]?.presses == 0 { keys.removeValue(forKey: key) }
        }
    }

    mutating func finish(at time: UInt64) -> KeyboardSession {
        for key in heldSince.keys { release(key, at: time) }
        let elapsed = time >= startedAt ? time - startedAt : 0
        return KeyboardSession(keys: keys, duration: .nanoseconds(Int64(clamping: elapsed)))
    }

    private static func isShortcutModifier(_ key: Int64) -> Bool {
        key != kVK_Function && modifierMask(for: key) != nil
    }

    private static func modifierMask(for key: Int64) -> UInt64? {
        switch Int(key) {
        case kVK_Control: UInt64(NX_DEVICELCTLKEYMASK)
        case kVK_RightControl: UInt64(NX_DEVICERCTLKEYMASK)
        case kVK_Shift: UInt64(NX_DEVICELSHIFTKEYMASK)
        case kVK_RightShift: UInt64(NX_DEVICERSHIFTKEYMASK)
        case kVK_Option: UInt64(NX_DEVICELALTKEYMASK)
        case kVK_RightOption: UInt64(NX_DEVICERALTKEYMASK)
        case kVK_Command: UInt64(NX_DEVICELCMDKEYMASK)
        case kVK_RightCommand: UInt64(NX_DEVICERCMDKEYMASK)
        case kVK_Function: CGEventFlags.maskSecondaryFn.rawValue
        default: nil
        }
    }
}
