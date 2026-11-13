import AppKit
import Carbon
import CoreGraphics

final class InputLock: ObservableObject {
    @Published private(set) var keyboardLocked = false
    @Published private(set) var pointerLocked = false
    @Published private(set) var ready = false
    @Published private(set) var issue: String?
    @Published private(set) var lastKeyboardActivity: KeyboardSession?

    var onShortcut: ((String) -> Void)?
    var onLocksChanged: ((_ didLock: Bool, _ automaticPattern: PawPattern?) -> Void)?
    var onKeyboardSessionEnded: (() -> Void)?
    @Published var keyboardShortcut = Shortcut.keyboard {
        didSet { filter.keyboardShortcut = keyboardShortcut }
    }
    @Published var pointerShortcut = Shortcut.pointer {
        didSet { filter.pointerShortcut = pointerShortcut }
    }
    @Published var lockShortcut = Shortcut.lock {
        didSet { filter.lockShortcut = lockShortcut }
    }
    @Published var recordingShortcut = false {
        didSet {
            filter.recordingShortcut = recordingShortcut
            updatePawHoldTimer()
        }
    }
    var automaticLockEnabled = false {
        didSet {
            filter.automaticLockEnabled = automaticLockEnabled
            updatePawHoldTimer()
        }
    }
    var automaticLockRules: AutomaticLockRules {
        get { filter.automaticLockRules }
        set {
            filter.automaticLockRules = newValue
            updatePawHoldTimer()
        }
    }

    private var filter = InputFilter()
    private var eventTap: CFMachPort?
    private var eventSource: CFRunLoopSource?
    private var permissionTimer: Timer?
    private var pawHoldTimer: Timer?
    private var scheduledPawHold: UInt64?

    var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func refresh(prompt: Bool = false) {
        if prompt && !accessibilityTrusted {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        guard accessibilityTrusted else {
            if eventTap != nil { stop() }
            issue = String(localized: "Allow Cat Is Coming in Privacy & Security › Accessibility.")
            startPermissionChecks()
            return
        }
        if let eventTap, CFMachPortIsValid(eventTap), CGEvent.tapIsEnabled(tap: eventTap) {
            stopPermissionChecks()
            return
        }
        if eventTap != nil { stop() }

        let events = InputFilter.keyboardEvents + InputFilter.pointerEvents
        let mask = events.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: inputTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            issue = String(localized: "macOS couldn’t start the input filter. Check the permission and reopen the app.")
            // Allow time for the grant to reach Core Graphics as well as Accessibility.
            if prompt { startPermissionChecks() }
            return
        }
        eventTap = tap
        eventSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        stopPermissionChecks()
        ready = true
        issue = nil
    }

    func stop() {
        stopPermissionChecks()
        unlockAll()
        if let eventSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        eventSource = nil
        eventTap = nil
        ready = false

        var freshFilter = InputFilter()
        freshFilter.keyboardShortcut = filter.keyboardShortcut
        freshFilter.pointerShortcut = filter.pointerShortcut
        freshFilter.recordingShortcut = filter.recordingShortcut
        freshFilter.automaticLockEnabled = automaticLockEnabled
        freshFilter.automaticLockRules = automaticLockRules
        filter = freshFilter
    }

    func releaseForSessionChange() {
        unlockAll()
        filter.resetPawDetection()
        updatePawHoldTimer()
    }

    private func startPermissionChecks() {
        guard permissionTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            MainActor.assumeIsolated { self.refresh() }
        }
        timer.tolerance = 0.2
        permissionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopPermissionChecks() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    @discardableResult
    func perform(_ action: InputFilter.Action, at time: UInt64 = DispatchTime.now().uptimeNanoseconds) -> String? {
        if action == .unlockAll {
            unlockAll(at: time)
            return String(localized: "Keyboard and mouse unlocked")
        }
        guard ready else { return nil }
        let locking = action == .toggleKeyboard ? !keyboardLocked : !pointerLocked
        let message: String
        switch action {
        case .lockAll:
            guard !keyboardLocked || !pointerLocked,
                  lockInputs(keyboard: !keyboardLocked, pointer: !pointerLocked, at: time) else { return nil }
            return String(localized: "Keyboard and mouse locked")
        case .toggleKeyboard:
            if locking {
                guard lockInputs(keyboard: true, pointer: false, at: time) else { return nil }
                return String(localized: "Keyboard locked")
            }
            filter.endKeyboardLock()
            updatePawHoldTimer()
            keyboardLocked = false
            finishKeyboardActivity(at: time)
            message = String(localized: "Keyboard unlocked")
        case .togglePointer:
            if locking {
                guard lockInputs(keyboard: false, pointer: true, at: time) else { return nil }
                return String(localized: "Mouse locked")
            }
            filter.pointerAnchor = nil
            pointerLocked = false
            message = String(localized: "Mouse unlocked")
        case .unlockAll:
            return nil
        }

        issue = nil
        reportLocksChanged(didLock: false)
        return message
    }

    private func lockInputs(
        keyboard: Bool, pointer: Bool, at time: UInt64,
        automaticPattern: PawPattern? = nil, suppressing key: Int64? = nil
    ) -> Bool {
        guard !IsSecureEventInputEnabled() else {
            if automaticPattern != nil {
                filter.resetPawDetection()
                updatePawHoldTimer()
                return false
            }
            issue = String(localized: "Secure keyboard entry is active. Leave the protected field and try again.")
            return false
        }
        if pointer {
            guard let position = CGEvent(source: nil)?.location,
                  CGWarpMouseCursorPosition(position) == .success else {
                issue = String(localized: "macOS couldn’t freeze the pointer.")
                return false
            }
            filter.pointerAnchor = position
            pointerLocked = true
        }
        if keyboard {
            filter.beginKeyboardLock(at: time, automatically: automaticPattern != nil, suppressing: key)
            updatePawHoldTimer()
            keyboardLocked = true
        }
        issue = nil
        reportLocksChanged(didLock: true, automaticPattern: automaticPattern)
        return true
    }

    func unlockAll(at time: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        let wasLocked = keyboardLocked || pointerLocked
        filter.endKeyboardLock()
        updatePawHoldTimer()
        filter.pointerAnchor = nil
        keyboardLocked = false
        pointerLocked = false
        finishKeyboardActivity(at: time)
        if wasLocked { reportLocksChanged(didLock: false) }
    }

    fileprivate func allows(_ type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            releaseForSessionChange()
            ready = false
            issue = String(localized: "macOS interrupted the input filter. Click Try Again to restart it.")
            return true
        }
        defer {
            if automaticLockEnabled && (
                InputFilter.keyboardEvents.contains(type) || InputFilter.intentionalPointerEvents.contains(type)
            ) {
                updatePawHoldTimer()
            }
        }
        switch filter.handle(type, event: event) {
        case .pass:
            return true
        case .discard:
            return false
        case .freeze(let point):
            if CGWarpMouseCursorPosition(point) != .success {
                unlockAll()
                issue = String(localized: "macOS stopped freezing the pointer.")
                return true
            }
            return false
        case .perform(let action):
            let endsKeyboardSession = keyboardLocked && (action == .toggleKeyboard || action == .unlockAll)
            if let message = perform(action, at: event.timestamp), !isLockingAction(action), !endsKeyboardSession {
                Task { @MainActor [weak self] in self?.onShortcut?(message) }
            }
            return false
        case .detectPaws(let pattern):
            // A release must reach the foreground app if its original press did.
            let key = type == .keyDown ? event.getIntegerValueField(.keyboardEventKeycode) : nil
            let locked = lockForPaws(pattern, at: event.timestamp, suppressing: key)
            return key == nil || !locked
        }
    }

    private func updatePawHoldTimer() {
        let deadline = filter.pawHoldDeadline
        guard deadline != scheduledPawHold else { return }
        pawHoldTimer?.invalidate()
        pawHoldTimer = nil
        scheduledPawHold = deadline
        guard let deadline else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        let delay = Double(deadline - min(deadline, now)) / 1_000_000_000
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPawHold() }
        }
        pawHoldTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func checkPawHold() {
        scheduledPawHold = nil
        pawHoldTimer = nil
        let now = DispatchTime.now().uptimeNanoseconds
        if let pattern = filter.detectHeldPaws(at: now) {
            _ = lockForPaws(pattern, at: now)
        } else {
            updatePawHoldTimer()
        }
    }

    private func lockForPaws(_ pattern: PawPattern, at time: UInt64, suppressing key: Int64? = nil) -> Bool {
        guard ready, automaticLockEnabled, !keyboardLocked, !recordingShortcut else { return false }
        return lockInputs(keyboard: true, pointer: false, at: time, automaticPattern: pattern, suppressing: key)
    }

    private func finishKeyboardActivity(at time: UInt64) {
        guard let session = filter.finishKeyboardActivity(at: time) else { return }
        // Deliver the report after returning from the event tap.
        Task { @MainActor [weak self] in
            guard let self else { return }
            lastKeyboardActivity = session
            if !keyboardLocked { onKeyboardSessionEnded?() }
        }
    }

    private func isLockingAction(_ action: InputFilter.Action) -> Bool {
        switch action {
        case .toggleKeyboard: keyboardLocked
        case .togglePointer: pointerLocked
        case .lockAll: true
        case .unlockAll: false
        }
    }

    private func reportLocksChanged(didLock: Bool, automaticPattern: PawPattern? = nil) {
        let keyboard = keyboardLocked
        let pointer = pointerLocked
        // Window and notification work must run outside the Core Graphics callback.
        Task { @MainActor [weak self] in
            guard let self, keyboard == keyboardLocked, pointer == pointerLocked else { return }
            onLocksChanged?(didLock, automaticPattern)
        }
    }

}

// Core Graphics invokes the callback on the main run loop where the tap is installed.
nonisolated private func inputTapCallback(
    _: CGEventTapProxy, type: CGEventType, event: CGEvent, context: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let context else { return Unmanaged.passUnretained(event) }
    let lock = Unmanaged<InputLock>.fromOpaque(context).takeUnretainedValue()
    // The event remains owned by Core Graphics for the duration of this synchronous call.
    nonisolated(unsafe) let mainRunLoopEvent = event
    let allowed = MainActor.assumeIsolated {
        lock.allows(type, event: mainRunLoopEvent)
    }
    return allowed ? Unmanaged.passUnretained(event) : nil
}
