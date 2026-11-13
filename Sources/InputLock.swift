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
    var onLocksChanged: ((_ didLock: Bool) -> Void)?
    var onKeyboardSessionEnded: (() -> Void)?
    var keyboardShortcut: Shortcut {
        get { filter.keyboardShortcut }
        set { filter.keyboardShortcut = newValue }
    }
    var pointerShortcut: Shortcut {
        get { filter.pointerShortcut }
        set { filter.pointerShortcut = newValue }
    }
    var recordingShortcut: Bool {
        get { filter.recordingShortcut }
        set { filter.recordingShortcut = newValue }
    }

    private var filter = InputFilter()
    private var eventTap: CFMachPort?
    private var eventSource: CFRunLoopSource?
    private var permissionTimer: Timer?

    func refresh(prompt: Bool = false) {
        if prompt {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        guard AXIsProcessTrusted() else {
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
        filter = freshFilter
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
        if locking, IsSecureEventInputEnabled() {
            issue = String(localized: "Secure keyboard entry is active. Leave the protected field and try again.")
            return nil
        }
        issue = nil

        let message: String
        switch action {
        case .toggleKeyboard:
            filter.keyboardLocked = locking
            keyboardLocked = locking
            if locking {
                filter.keyboardActivity = KeyboardActivity(startedAt: time)
            } else {
                finishKeyboardActivity(at: time)
            }
            message = locking ? String(localized: "Keyboard locked") : String(localized: "Keyboard unlocked")
        case .togglePointer:
            if locking {
                guard let position = CGEvent(source: nil)?.location,
                      CGWarpMouseCursorPosition(position) == .success else {
                    issue = String(localized: "macOS couldn’t freeze the pointer.")
                    return nil
                }
                filter.pointerAnchor = position
            } else {
                filter.pointerAnchor = nil
            }
            pointerLocked = locking
            message = locking ? String(localized: "Mouse locked") : String(localized: "Mouse unlocked")
        case .unlockAll:
            return nil
        }

        reportLocksChanged(didLock: locking)
        return message
    }

    func unlockAll(at time: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        let wasLocked = keyboardLocked || pointerLocked
        filter.keyboardLocked = false
        filter.pointerAnchor = nil
        keyboardLocked = false
        pointerLocked = false
        finishKeyboardActivity(at: time)
        if wasLocked { reportLocksChanged(didLock: false) }
    }

    fileprivate func allows(_ type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            unlockAll()
            ready = false
            issue = String(localized: "macOS interrupted the input filter. Click Try Again to restart it.")
            return true
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
        }
    }

    private func finishKeyboardActivity(at time: UInt64) {
        guard var activity = filter.keyboardActivity else { return }
        filter.keyboardActivity = nil
        let session = activity.finish(at: time)
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
        case .unlockAll: false
        }
    }

    private func reportLocksChanged(didLock: Bool) {
        let keyboard = keyboardLocked
        let pointer = pointerLocked
        // Window and notification work must run outside the Core Graphics callback.
        Task { @MainActor [weak self] in
            guard let self, keyboard == keyboardLocked, pointer == pointerLocked else { return }
            onLocksChanged?(didLock)
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
