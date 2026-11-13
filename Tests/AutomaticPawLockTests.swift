import Carbon
import CoreGraphics
import Darwin

@main
@MainActor
struct AutomaticPawLockTests {
    private static var failures = 0

    static func main() {
        disabledByDefault()
        detectsSettlingWithoutAnotherKeystroke()
        cancelsSettlingOnRelease()
        detectsQuickLanding()
        detectsCrossing()
        detectsRollingPawSteps()
        ignoresOrdinaryInput()
        stopsDetectionWhenDisabled()
        resumesAfterEmergencyUnlock()
        retainsOnlyBlockedActivity()
        detectsAnUninterruptedSingleKeyHold()
        ignoresSpaceUsedWithOtherInput()
        respectsConfiguredTriggers()
        respectsConfiguredCrossingThresholds()
        if failures != 0 { exit(EXIT_FAILURE) }
        print("14 automatic paw lock scenarios passed")
    }

    private static func disabledByDefault() {
        var filter = InputFilter()
        expect(send(&filter, kVK_ANSI_A, 0).passes, "Disabled detection passes through keys")
        _ = send(&filter, kVK_ANSI_S, 20)
        _ = send(&filter, kVK_ANSI_D, 40)
        expect(send(&filter, kVK_ANSI_F, 60).passes, "Disabled detection passes through a landing")
        expect(filter.pawHoldDeadline == nil, "Disabled detection does not schedule a hold check")
    }

    private static func detectsSettlingWithoutAnotherKeystroke() {
        var filter = enabledFilter()
        _ = send(&filter, kVK_ANSI_A, 0)
        _ = send(&filter, kVK_ANSI_S, 70)
        _ = send(&filter, kVK_ANSI_D, 140)
        expect(filter.pawHoldDeadline == ns(340), "Hold check starts when the third key goes down")
        expect(filter.detectHeldPaws(at: ns(339)) == nil, "Three keys need 200 ms of overlap")
        expect(filter.detectHeldPaws(at: ns(340)) == .settling, "The hold timer detects a motionless cat")
    }

    private static func cancelsSettlingOnRelease() {
        var filter = enabledFilter()
        _ = send(&filter, kVK_ANSI_A, 0)
        _ = send(&filter, kVK_ANSI_S, 40)
        _ = send(&filter, kVK_ANSI_D, 80)
        _ = send(&filter, kVK_ANSI_S, 240, down: false)
        expect(filter.pawHoldDeadline == nil, "Lifting a key cancels a pending hold")
        expect(filter.detectHeldPaws(at: ns(280)) == nil, "A stale timer cannot lock after a release")
    }

    private static func detectsQuickLanding() {
        var filter = enabledFilter()
        _ = send(&filter, kVK_ANSI_A, 0)
        _ = send(&filter, kVK_ANSI_S, 25)
        _ = send(&filter, kVK_ANSI_D, 45)
        expect(send(&filter, kVK_ANSI_F, 75).pattern == .landing, "Four keys trigger immediately")
    }

    private static func detectsCrossing() {
        var filter = enabledFilter()
        _ = send(&filter, kVK_ANSI_A, 0)
        _ = send(&filter, kVK_ANSI_S, 40)
        expect(send(&filter, kVK_ANSI_A, 85, down: false).passes, "One pair is not enough")
        _ = send(&filter, kVK_ANSI_S, 90, down: false)
        _ = send(&filter, kVK_ANSI_K, 300)
        _ = send(&filter, kVK_ANSI_L, 340)
        expect(send(&filter, kVK_ANSI_K, 380, down: false).pattern == .crossing, "Two distinct pairs detect a crossing")
    }

    private static func detectsRollingPawSteps() {
        var filter = enabledFilter()
        _ = send(&filter, kVK_ANSI_A, 0)
        _ = send(&filter, kVK_ANSI_S, 30)
        _ = send(&filter, kVK_ANSI_K, 170)
        _ = send(&filter, kVK_ANSI_L, 200)
        _ = send(&filter, kVK_ANSI_A, 220, down: false)
        _ = send(&filter, kVK_ANSI_S, 230, down: false)
        expect(send(&filter, kVK_ANSI_K, 255, down: false).pattern == .crossing,
               "The second paw can land before the first one lifts")
    }

    private static func ignoresOrdinaryInput() {
        var filter = enabledFilter()
        _ = send(&filter, kVK_ANSI_A, 0)
        expect(send(&filter, kVK_ANSI_A, 40, repeating: true).passes, "One repeating key is not a paw")
        _ = send(&filter, kVK_ANSI_S, 60)
        _ = send(&filter, kVK_ANSI_A, 74, down: false)
        _ = send(&filter, kVK_ANSI_D, 110)
        _ = send(&filter, kVK_ANSI_S, 127, down: false)
        _ = send(&filter, kVK_ANSI_F, 150)
        expect(send(&filter, kVK_ANSI_D, 161, down: false).passes, "Rolling typing does not count as two paw steps")
        _ = send(&filter, kVK_ANSI_F, 178, down: false)
        for (index, key) in [kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_D, kVK_ANSI_F].enumerated() {
            expect(send(&filter, key, 200 + index * 15, flags: .maskCommand).passes, "Command chords never auto-lock")
        }
        expect(filter.pawHoldDeadline == nil, "Ordinary input does not leave a hold pending")

        // Similar pairs with a shared key, or separated by over a second, do not match.
        for (secondStart, secondKeys) in [(250, (kVK_ANSI_S, kVK_ANSI_D)), (1_100, (kVK_ANSI_K, kVK_ANSI_L))] {
            filter = enabledFilter()
            _ = send(&filter, kVK_ANSI_A, 0)
            _ = send(&filter, kVK_ANSI_S, 25)
            _ = send(&filter, kVK_ANSI_A, 65, down: false)
            _ = send(&filter, kVK_ANSI_S, 75, down: false)
            _ = send(&filter, secondKeys.0, secondStart)
            _ = send(&filter, secondKeys.1, secondStart + 30)
            expect(send(&filter, secondKeys.0, secondStart + 75, down: false).passes,
                   "Crossing requires separate pairs within a second")
        }
    }

    private static func resumesAfterEmergencyUnlock() {
        var filter = enabledFilter()
        filter.recordingShortcut = true
        for (index, key) in [kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_D, kVK_ANSI_F].enumerated() {
            expect(send(&filter, key, index * 15).passes, "Recording a shortcut pauses detection")
        }
        filter = enabledFilter()
        _ = send(&filter, kVK_ANSI_A, 0)
        _ = send(&filter, kVK_ANSI_S, 20)
        _ = send(&filter, kVK_ANSI_D, 40)
        let trigger = send(&filter, kVK_ANSI_F, 60)
        expect(trigger.pattern == .landing, "Landing triggers before emergency unlock")
        filter.beginKeyboardLock(at: ns(60), automatically: true, suppressing: Int64(kVK_ANSI_F))
        expect(send(&filter, kVK_ANSI_X, 90).discarded, "Lock blocks subsequent typing")
        let unlock = send(&filter, kVK_Escape, 100, flags: [.maskShift, .maskControl])
        if case .perform(.unlockAll) = unlock {} else { expect(false, "Emergency shortcut still works") }
        filter.endKeyboardLock()
        _ = send(&filter, kVK_Escape, 115, down: false)
        expect(send(&filter, kVK_ANSI_A, 125, repeating: true).discarded, "Old paw keys cannot repeat into the foreground")
        expect(send(&filter, kVK_ANSI_X, 135, down: false).discarded, "A blocked keyup stays blocked after unlock")
        expect(send(&filter, kVK_ANSI_F, 145, down: false).discarded, "The triggering keyup stays blocked")
        for (index, key) in [kVK_ANSI_Z, kVK_ANSI_X, kVK_ANSI_C, kVK_ANSI_V].enumerated() {
            expect(send(&filter, key, 150 + index).passes, "New typing passes while rearming")
        }
        for key in [kVK_ANSI_Z, kVK_ANSI_X, kVK_ANSI_C, kVK_ANSI_V] {
            _ = send(&filter, key, 160, down: false)
        }
        for key in [kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_D] {
            expect(send(&filter, key, 165, down: false).passes, "A previously visible key still releases")
        }
        _ = send(&filter, kVK_ANSI_H, 240)
        _ = send(&filter, kVK_ANSI_J, 260)
        _ = send(&filter, kVK_ANSI_K, 280)
        expect(send(&filter, kVK_ANSI_L, 300).pattern == .landing, "The next landing can rearm after release")
    }

    private static func stopsDetectionWhenDisabled() {
        var filter = enabledFilter()
        _ = send(&filter, kVK_ANSI_A, 0)
        _ = send(&filter, kVK_ANSI_S, 35)
        _ = send(&filter, kVK_ANSI_D, 85)
        filter.automaticLockEnabled = false
        expect(filter.detectHeldPaws(at: ns(310)) == nil, "Disabling cancels a pending lock")
        filter.automaticLockEnabled = true
        expect(send(&filter, kVK_ANSI_F, 315).passes, "Re-enabling doesn't use old presses")
    }

    private static func retainsOnlyBlockedActivity() {
        var filter = enabledFilter()
        _ = send(&filter, kVK_ANSI_A, 0)
        _ = send(&filter, kVK_ANSI_S, 60)
        _ = send(&filter, kVK_ANSI_D, 120)
        filter.beginKeyboardLock(at: ns(320), automatically: true)
        _ = send(&filter, kVK_ANSI_A, 355, repeating: true)
        _ = send(&filter, kVK_ANSI_A, 380, down: false)
        let mouse = CGEvent(source: nil)!
        expect(filter.handle(.leftMouseDown, event: mouse).passes, "Automatic keyboard lock leaves the pointer available")
        expect(filter.keyboardActivity?.keys[Int64(kVK_ANSI_A)]?.presses == 1, "The held paw counts once")
        expect(filter.keyboardActivity?.keys[Int64(kVK_ANSI_A)]?.heldNanoseconds == ns(60),
               "A pre-lock key only contributes its blocked hold time")
    }

    private static func enabledFilter() -> InputFilter {
        var filter = InputFilter()
        filter.automaticLockEnabled = true
        return filter
    }

    private static func detectsAnUninterruptedSingleKeyHold() {
        var filter = enabledFilter()
        _ = send(&filter, kVK_Space, 0)
        expect(filter.pawHoldDeadline == nil, "Space detection is off by default")
        _ = send(&filter, kVK_Space, 50, down: false)
        filter.automaticLockRules.singleKeyEnabled = true

        expect(send(&filter, kVK_Space, 100).passes, "An ordinary space passes immediately")
        expect(send(&filter, kVK_Space, 150, down: false).passes, "A short space releases normally")
        expect(filter.detectHeldPaws(at: ns(2_200)) == nil, "A released space cannot trigger")
        _ = send(&filter, kVK_ANSI_A, 2_250)
        expect(filter.detectHeldPaws(at: ns(4_250)) == .singleKeyHold, "Letter keys can also trigger after a long hold")
        _ = send(&filter, kVK_ANSI_A, 2_300, down: false)

        _ = send(&filter, kVK_Space, 2_400)
        expect(send(&filter, kVK_Space, 2_950, repeating: true).passes, "Space repeat still passes before locking")
        expect(filter.detectHeldPaws(at: ns(4_399)) == nil, "The hold needs two full seconds")
        expect(filter.detectHeldPaws(at: ns(4_400)) == .singleKeyHold, "Space can trigger without more input")
        filter.beginKeyboardLock(at: ns(4_400), automatically: true)
        expect(send(&filter, kVK_Space, 4_450, repeating: true).discarded, "Lock stops space repeat")
        filter.endKeyboardLock()
        expect(send(&filter, kVK_Space, 4_500, repeating: true).discarded, "Repeats stay quiet until release")
        expect(filter.detectHeldPaws(at: ns(6_400)) == nil, "Unlock does not immediately rearm the same press")
        expect(send(&filter, kVK_Space, 6_450, down: false).passes, "The foreground app receives the matching release")
        _ = send(&filter, kVK_Space, 6_550)
        expect(filter.detectHeldPaws(at: ns(8_550)) == .singleKeyHold, "A fresh space can trigger again")
    }

    private static func ignoresSpaceUsedWithOtherInput() {
        var filter = enabledFilter()
        filter.automaticLockRules.singleKeyEnabled = true
        _ = send(&filter, kVK_Space, 0)
        _ = send(&filter, kVK_ANSI_A, 100)
        _ = send(&filter, kVK_ANSI_A, 150, down: false)
        expect(filter.pawHoldDeadline == nil, "Typing cancels this space hold even after the other key releases")
        _ = send(&filter, kVK_Space, 200, down: false)
        _ = send(&filter, kVK_Space, 300)
        let mouse = CGEvent(source: nil)!
        expect(filter.handle(.leftMouseDragged, event: mouse).passes, "Space plus drag passes through")
        expect(filter.pawHoldDeadline == nil, "Dragging cancels this space hold")
        _ = send(&filter, kVK_Space, 400, down: false)
        _ = send(&filter, kVK_Space, 500, flags: .maskCommand)
        expect(filter.pawHoldDeadline == nil, "Command-space never starts the timer")
    }

    private static func respectsConfiguredTriggers() {
        var filter = enabledFilter()
        filter.automaticLockRules.landingKeyCount = 5
        filter.automaticLockRules.landingWindowMS = 80
        filter.automaticLockRules.settlingEnabled = false
        for (index, key) in [kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_D, kVK_ANSI_F].enumerated() {
            expect(send(&filter, key, index * 20).passes, "Four keys are below the new landing threshold")
        }
        expect(filter.pawHoldDeadline == nil, "Disabling settling leaves no hold timer")
        expect(send(&filter, kVK_ANSI_G, 81).passes, "Five presses must be within the configured window")
        expect(send(&filter, kVK_ANSI_H, 90).pattern == .landing, "Five recent presses can still trigger")

        filter = enabledFilter()
        filter.automaticLockRules.landingEnabled = false
        filter.automaticLockRules.settlingKeyCount = 4
        filter.automaticLockRules.settlingWindowMS = 250
        filter.automaticLockRules.settlingHoldMS = 500
        _ = send(&filter, kVK_ANSI_A, 0)
        _ = send(&filter, kVK_ANSI_S, 75)
        _ = send(&filter, kVK_ANSI_D, 150)
        expect(filter.pawHoldDeadline == nil, "Settling now requires a fourth key")
        expect(send(&filter, kVK_ANSI_F, 225).passes, "Landing stays disabled")
        expect(filter.detectHeldPaws(at: ns(724)) == nil, "The configured overlap is required")
        expect(filter.detectHeldPaws(at: ns(725)) == .settling, "The new settling thresholds are applied")

        filter = enabledFilter()
        filter.automaticLockRules.singleKeyEnabled = true
        filter.automaticLockRules.singleKeyHoldMS = 3_000
        _ = send(&filter, kVK_Space, 0)
        expect(filter.detectHeldPaws(at: ns(2_000)) == nil, "Space uses the configured hold time")
        expect(filter.detectHeldPaws(at: ns(3_000)) == .singleKeyHold, "The configured single-key deadline is honored")
        filter.automaticLockRules.singleKeyEnabled = false
        expect(filter.pawHoldDeadline == nil, "Changing settings cancels a pending hold")
    }

    private static func respectsConfiguredCrossingThresholds() {
        func crossing(enabled: Bool = true, pairMS: Int = 70, overlapMS: Int = 40, gapMS: Int = 400) -> PawPattern? {
            var filter = enabledFilter()
            filter.automaticLockRules.crossingEnabled = enabled
            filter.automaticLockRules.crossingPairWindowMS = pairMS
            filter.automaticLockRules.crossingOverlapMS = overlapMS
            filter.automaticLockRules.crossingWindowMS = gapMS
            _ = send(&filter, kVK_ANSI_A, 0)
            _ = send(&filter, kVK_ANSI_S, 65)
            _ = send(&filter, kVK_ANSI_A, 110, down: false)
            _ = send(&filter, kVK_ANSI_S, 120, down: false)
            _ = send(&filter, kVK_ANSI_K, 350)
            _ = send(&filter, kVK_ANSI_L, 415)
            return send(&filter, kVK_ANSI_K, 460, down: false).pattern
        }
        expect(crossing() == .crossing, "The configured crossing accepts both pairs")
        expect(crossing(enabled: false) == nil, "Crossing can be disabled independently")
        expect(crossing(pairMS: 60) == nil, "Both presses must fit within the pair window")
        expect(crossing(overlapMS: 50) == nil, "Both pairs must overlap long enough")
        expect(crossing(gapMS: 300) == nil, "The two pairs must start close enough together")
    }

    private static func send(
        _ filter: inout InputFilter, _ key: Int, _ time: Int,
        down: Bool = true, repeating: Bool = false, flags: CGEventFlags = []
    ) -> InputFilter.Decision {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: down)!
        event.timestamp = ns(time)
        event.flags = flags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeating ? 1 : 0)
        return filter.handle(down ? .keyDown : .keyUp, event: event)
    }

    private static func ns(_ milliseconds: Int) -> UInt64 {
        UInt64(milliseconds) * 1_000_000
    }

    private static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            print("FAIL: \(message)")
            failures += 1
        }
    }
}

private extension InputFilter.Decision {
    var passes: Bool { if case .pass = self { true } else { false } }
    var discarded: Bool { if case .discard = self { true } else { false } }
    var pattern: PawPattern? { if case .detectPaws(let pattern) = self { pattern } else { nil } }
}
