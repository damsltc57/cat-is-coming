import AppKit
import Carbon
import ServiceManagement
import SwiftUI
import UserNotifications

@main
struct CatIsComingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            CatMenu(delegate: delegate, input: delegate.input)
        } label: {
            CatIcon(input: delegate.input)
        }
    }
}

private struct CatIcon: View {
    @ObservedObject var input: InputLock

    private static let lockedImage: NSImage? = {
        let renderer = ImageRenderer(content:
            Image("MenuBarCat")
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 6.5, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 9, height: 9)
                        .background(Color(red: 0.65, green: 0.20, blue: 0.22), in: Circle())
                        .padding(1)
                        .background(Color(red: 0.97, green: 0.95, blue: 0.89), in: Circle())
                }
        )
        renderer.scale = 3
        guard let bitmap = renderer.cgImage else { return nil }
        return NSImage(cgImage: bitmap, size: NSSize(width: 20, height: 20))
    }()

    var body: some View {
        let locked = input.keyboardLocked || input.pointerLocked
        let icon = locked ? Self.lockedImage.map { Image(nsImage: $0) } : nil
        (icon ?? Image("MenuBarCat"))
            .renderingMode(.original)
            .accessibilityLabel("Cat Is Coming")
            .accessibilityValue(lockStatus)
    }

    private var lockStatus: Text {
        switch (input.keyboardLocked, input.pointerLocked) {
        case (true, true): Text("Keyboard and mouse locked")
        case (true, false): Text("Keyboard locked")
        case (false, true): Text("Mouse locked")
        case (false, false): Text("")
        }
    }
}

private struct CatMenu: View {
    @ObservedObject var delegate: AppDelegate
    @ObservedObject var input: InputLock

    var body: some View {
        shortcutButton(
            input.keyboardLocked ? String(localized: "Unlock Keyboard") : String(localized: "Lock Keyboard"),
            shortcut: input.keyboardShortcut
        ) {
            input.perform(.toggleKeyboard)
        }
        .disabled(!input.ready)
        shortcutButton(
            input.pointerLocked ? String(localized: "Unlock Mouse") : String(localized: "Lock Mouse"),
            shortcut: input.pointerShortcut
        ) {
            input.perform(.togglePointer)
        }
        .disabled(!input.ready)
        shortcutButton(String(localized: "Lock Everything"), shortcut: input.lockShortcut) {
            input.perform(.lockAll)
        }
        .disabled(!input.ready || (input.keyboardLocked && input.pointerLocked))
        Button("Unlock Everything") {
            input.unlockAll()
        }
        .keyboardShortcut(Shortcut.unlock.menuKeyEquivalent)
        .disabled(!input.keyboardLocked && !input.pointerLocked)

        if input.lastKeyboardActivity != nil {
            Button("View Last Paw Activity…") {
                delegate.showHeatmap()
            }
        }

        if let issue = input.issue {
            Divider()
            Text(issue)
        }
        if !input.ready {
            Button("Allow Input Locking…") {
                input.refresh(prompt: true)
            }
            Button("Try Again") {
                input.refresh()
            }
        }

        if delegate.canEnableNotifications {
            Divider()
            Button("Allow Notifications…") {
                Task { await delegate.requestNotifications() }
            }
        }

        Divider()
        Toggle("Open at Login", isOn: Binding(
            get: { delegate.opensAtLogin },
            set: { delegate.setOpenAtLogin($0) }
        ))
        if let issue = delegate.loginIssue {
            Text(issue)
            Button("Open Login Items…") {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
        Button("Settings…") {
            delegate.showSettings()
        }
        Button("Quit Cat Is Coming") {
            NSApp.terminate(nil)
        }
    }

    private func shortcutButton(_ title: String, shortcut: Shortcut, action: @escaping () -> Void) -> some View {
        let equivalent = shortcut.menuKeyEquivalent
        let menuTitle = equivalent == nil ? "\(title)  \(shortcut.label)" : title
        return Button(menuTitle, action: action)
            .keyboardShortcut(input.recordingShortcut ? nil : equivalent)
    }
}

private extension Shortcut {
    var menuKeyEquivalent: KeyboardShortcut? {
        let equivalent: KeyEquivalent
        switch Int(keyCode) {
        case kVK_Escape: equivalent = .escape
        case kVK_Space: equivalent = .space
        case kVK_Tab: equivalent = .tab
        case kVK_Return, kVK_ANSI_KeypadEnter: equivalent = .return
        case kVK_Delete: equivalent = .delete
        case kVK_ForwardDelete: equivalent = .deleteForward
        case kVK_LeftArrow: equivalent = .leftArrow
        case kVK_RightArrow: equivalent = .rightArrow
        case kVK_UpArrow: equivalent = .upArrow
        case kVK_DownArrow: equivalent = .downArrow
        case kVK_Home: equivalent = .home
        case kVK_End: equivalent = .end
        case kVK_PageUp: equivalent = .pageUp
        case kVK_PageDown: equivalent = .pageDown
        default:
            if let functionKey = functionKeyEquivalent {
                equivalent = functionKey
            } else {
                let character = key.lowercased()
                guard character.count == 1, let value = character.first else { return nil }
                equivalent = KeyEquivalent(value)
            }
        }

        let flags = CGEventFlags(rawValue: modifierFlags)
        var modifiers: SwiftUI.EventModifiers = []
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        return KeyboardShortcut(equivalent, modifiers: modifiers, localization: .custom)
    }

    private var functionKeyEquivalent: KeyEquivalent? {
        let codes = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        ]
        guard let index = codes.firstIndex(of: Int(keyCode)),
              let scalar = UnicodeScalar(NSF1FunctionKey + index) else { return nil }
        return KeyEquivalent(Character(scalar))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject, UNUserNotificationCenterDelegate {
    let input = InputLock()
    @Published private(set) var meowsEnabled = UserDefaults.standard.bool(forKey: "meowsEnabled")
    @Published private(set) var automaticLockEnabled = UserDefaults.standard.bool(forKey: "automaticLockEnabled")
    @Published private(set) var automaticLockRules: AutomaticLockRules = {
        guard let data = UserDefaults.standard.data(forKey: "automaticLockRules"),
              var rules = try? JSONDecoder().decode(AutomaticLockRules.self, from: data) else { return .init() }
        rules.clampThresholds()
        return rules
    }()
    @Published private(set) var opensAtLogin = false
    @Published private(set) var loginIssue: String?
    @Published private(set) var notificationStatus = ""
    @Published private(set) var canEnableNotifications = false

    private let defaults = UserDefaults.standard
    private let notifications = UNUserNotificationCenter.current()
    private let lockNotice = LockNoticeController()
    private let lockMeow = Bundle.main.url(forResource: "LockMeow", withExtension: "wav")
        .flatMap { NSSound(contentsOf: $0, byReference: false) }
    private let unlockMeow = Bundle.main.url(forResource: "UnlockMeow", withExtension: "wav")
        .flatMap { NSSound(contentsOf: $0, byReference: false) }
    private var playingMeow: NSSound?
    private var firstLaunchWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var heatmapWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        input.keyboardShortcut = shortcut(for: .keyboard)
        input.pointerShortcut = shortcut(for: .pointer)
        input.lockShortcut = shortcut(for: .lockAll)
        input.automaticLockEnabled = automaticLockEnabled
        input.automaticLockRules = automaticLockRules
        notifications.delegate = self
        input.onShortcut = { [weak self] message in
            self?.notify(message)
        }
        input.onKeyboardSessionEnded = { [weak self] in
            self?.lockNotice.showKeyboardReport { [weak self] in self?.showHeatmap() }
        }
        input.onLocksChanged = { [weak self] didLock, automaticPattern in
            guard let self else { return }
            lockNotice.update(
                keyboard: input.keyboardLocked, pointer: input.pointerLocked,
                show: didLock, automaticPattern: automaticPattern
            )
            guard meowsEnabled else { return }
            playingMeow?.stop()
            playingMeow = didLock ? lockMeow : unlockMeow
            playingMeow?.play()
        }
        input.refresh()
        refreshLoginStatus()
        Task { await prepareFirstLaunch() }
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshNotifications), name: NSMenu.didBeginTrackingNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(releaseLocks(_:)), name: NSWorkspace.willSleepNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(releaseLocks(_:)),
            name: NSWorkspace.sessionDidResignActiveNotification, object: nil
        )
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        input.refresh()
        refreshLoginStatus()
        refreshNotifications()
    }

    func applicationWillTerminate(_ notification: Notification) {
        input.stop()
    }

    func setMeowsEnabled(_ enabled: Bool) {
        meowsEnabled = enabled
        defaults.set(enabled, forKey: "meowsEnabled")
        if !enabled {
            playingMeow?.stop()
            playingMeow = nil
        }
    }

    func setAutomaticLockEnabled(_ enabled: Bool) {
        automaticLockEnabled = enabled
        input.automaticLockEnabled = enabled
        defaults.set(enabled, forKey: "automaticLockEnabled")
    }

    func setAutomaticLockRules(_ rules: AutomaticLockRules) {
        automaticLockRules = rules
        input.automaticLockRules = rules
        defaults.set(try? JSONEncoder().encode(rules), forKey: "automaticLockRules")
    }

    private func prepareFirstLaunch() async {
        let notificationSettings = await notifications.notificationSettings()
        updateNotificationStatus(notificationSettings)
        guard let setup = FirstLaunchSetup.prepare(
            defaults: defaults,
            accessibilityTrusted: input.accessibilityTrusted,
            notificationStatus: notificationSettings.authorizationStatus
        ) else { return }

        let view = FirstLaunchSetupView(
            input: input,
            setup: setup,
            enableNotifications: { [weak self] in
                guard let self else { return false }
                return await requestNotifications()
            },
            close: { [weak self] in self?.firstLaunchWindow?.close() }
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Cat Is Coming"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        firstLaunchWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if setup.requestsAccessibility { input.refresh(prompt: true) }
    }

    func showSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: ShortcutSettings(delegate: self, input: input))
            let window = NSWindow(contentViewController: controller)
            window.title = String(localized: "Cat Is Coming Settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showHeatmap() {
        guard let session = input.lastKeyboardActivity else { return }
        let controller = NSHostingController(rootView: HeatmapView(session: session))
        if let heatmapWindow {
            heatmapWindow.contentViewController = controller
            heatmapWindow.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(contentViewController: controller)
            window.title = String(localized: "Paws on the Keyboard")
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.center()
            window.makeKeyAndOrderFront(nil)
            heatmapWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func releaseLocks(_ notification: Notification) {
        input.releaseForSessionChange()
    }

    func shortcut(for target: ShortcutTarget) -> Shortcut {
        guard let data = defaults.data(forKey: target.rawValue),
              let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data) else {
            return target.defaultShortcut
        }
        return shortcut
    }

    func setShortcut(_ shortcut: Shortcut, for target: ShortcutTarget) {
        defaults.set(try? JSONEncoder().encode(shortcut), forKey: target.rawValue)
        switch target {
        case .keyboard: input.keyboardShortcut = shortcut
        case .pointer: input.pointerShortcut = shortcut
        case .lockAll: input.lockShortcut = shortcut
        }
    }

    func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        opensAtLogin = status == .enabled || status == .requiresApproval
        loginIssue = status == .requiresApproval ? String(localized: "Confirm the login item in System Settings.") : nil
    }

    func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLoginStatus()
        } catch {
            refreshLoginStatus()
            loginIssue = String(localized: "Couldn’t change the login setting. \(error.localizedDescription)")
        }
    }

    @objc private func refreshNotifications() {
        Task { await refreshNotificationStatus() }
    }

    func refreshNotificationStatus() async {
        updateNotificationStatus(await notifications.notificationSettings())
    }

    private func updateNotificationStatus(_ settings: UNNotificationSettings) {
        let showsAlerts = settings.alertSetting == .enabled && settings.alertStyle != .none
        switch settings.authorizationStatus {
        case .authorized:
            canEnableNotifications = !showsAlerts
            notificationStatus = showsAlerts
                ? String(localized: "Notifications are allowed.")
                : String(localized: "Allow banners in System Settings › Notifications.")
        case .denied:
            canEnableNotifications = true
            notificationStatus = String(localized: "Allow Cat Is Coming in System Settings › Notifications.")
        default:
            canEnableNotifications = true
            notificationStatus = String(localized: "Allow banners to get notified after using an unlock shortcut.")
        }
    }

    @discardableResult
    func requestNotifications() async -> Bool {
        let settings = await notifications.notificationSettings()
        updateNotificationStatus(settings)
        guard canEnableNotifications else { return true }

        switch settings.authorizationStatus {
        case .denied, .authorized:
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                return NSWorkspace.shared.open(url)
            }
            return false
        default:
            do {
                _ = try await notifications.requestAuthorization(options: [.alert])
                await refreshNotificationStatus()
                return true
            } catch {
                notificationStatus = error.localizedDescription
                return false
            }
        }
    }

    private func notify(_ message: String) {
        Task {
            let settings = await notifications.notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "Cat Is Coming"
            content.body = message
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await notifications.add(request)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner]
    }
}
