import AppKit
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

    var body: some View {
        let locked = input.keyboardLocked || input.pointerLocked
        Image("MenuBarCat")
            .renderingMode(.original)
            .overlay(alignment: .bottomTrailing) {
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(2)
                        .background(.black, in: Circle())
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel("Cat Is Coming")
    }
}

private struct CatMenu: View {
    @ObservedObject var delegate: AppDelegate
    @ObservedObject var input: InputLock
    var body: some View {
        Button(input.keyboardLocked ? String(localized: "Unlock Keyboard") : String(localized: "Lock Keyboard")) {
            input.perform(.toggleKeyboard)
        }
        .disabled(!input.ready)
        Button(input.pointerLocked ? String(localized: "Unlock Mouse") : String(localized: "Lock Mouse")) {
            input.perform(.togglePointer)
        }
        .disabled(!input.ready)
        Button("Unlock Everything (\(Shortcut.unlock.label))") {
            input.unlockAll()
        }
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
}

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject, UNUserNotificationCenterDelegate {
    let input = InputLock()
    @Published private(set) var meowsEnabled = UserDefaults.standard.bool(forKey: "meowsEnabled")
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
    private var settingsWindow: NSWindow?
    private var heatmapWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        input.keyboardShortcut = shortcut(for: .keyboard)
        input.pointerShortcut = shortcut(for: .pointer)
        notifications.delegate = self
        input.onShortcut = { [weak self] message in
            self?.notify(message)
        }
        input.onKeyboardSessionEnded = { [weak self] in
            self?.lockNotice.showKeyboardReport { [weak self] in self?.showHeatmap() }
        }
        input.onLocksChanged = { [weak self] didLock in
            guard let self else { return }
            lockNotice.update(keyboard: input.keyboardLocked, pointer: input.pointerLocked, show: didLock)
            guard meowsEnabled else { return }
            playingMeow?.stop()
            playingMeow = didLock ? lockMeow : unlockMeow
            playingMeow?.play()
        }
        input.refresh()
        refreshLoginStatus()
        refreshNotifications()
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
        input.unlockAll()
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

    func requestNotifications() async {
        let settings = await notifications.notificationSettings()
        updateNotificationStatus(settings)
        guard canEnableNotifications else { return }

        switch settings.authorizationStatus {
        case .denied, .authorized:
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        default:
            do {
                _ = try await notifications.requestAuthorization(options: [.alert])
                await refreshNotificationStatus()
            } catch {
                notificationStatus = error.localizedDescription
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
