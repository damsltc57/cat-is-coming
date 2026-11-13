import AppKit
import Carbon
import SwiftUI

enum ShortcutTarget: String, CaseIterable, Identifiable {
    case keyboard = "keyboardShortcut"
    case pointer = "pointerShortcut"

    var id: Self { self }
    var title: String { self == .keyboard ? String(localized: "Lock Keyboard") : String(localized: "Lock Mouse") }
    var defaultShortcut: Shortcut { self == .keyboard ? .keyboard : .pointer }
    var other: Self { self == .keyboard ? .pointer : .keyboard }
}

struct ShortcutSettings: View {
    @ObservedObject var delegate: AppDelegate
    @ObservedObject var input: InputLock
    @State private var recording: ShortcutTarget?
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        Form {
            HStack(spacing: 8) {
                Image("CatArtwork")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)
                Text("Cat Is Coming")
                    .font(.title2.weight(.semibold))
            }
            Section("Global Shortcuts") {
                ForEach(ShortcutTarget.allCases) { target in
                    LabeledContent(target.title) {
                        Button(recording == target ? String(localized: "Press the shortcut…") : delegate.shortcut(for: target).label) {
                            startRecording(target)
                        }
                        .disabled(input.keyboardLocked || input.pointerLocked)
                    }
                }
                LabeledContent("Unlock Everything", value: Shortcut.unlock.label)
                if let message {
                    Text(message).foregroundStyle(.secondary)
                }
            }
            Section("Notifications") {
                Toggle("Meows", isOn: Binding(
                    get: { delegate.meowsEnabled },
                    set: { delegate.setMeowsEnabled($0) }
                ))
                Text(delegate.notificationStatus)
                if delegate.canEnableNotifications {
                    Button("Allow Notifications…") {
                        Task { await delegate.requestNotifications() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
        .fixedSize(horizontal: false, vertical: true)
        .task { await delegate.refreshNotificationStatus() }
        .onDisappear { stopRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            if recording != nil { stopRecording() }
        }
    }

    private func startRecording(_ target: ShortcutTarget) {
        stopRecording()
        recording = target
        input.recordingShortcut = true
        message = String(localized: "Use ⌃, ⌥, or ⌘ with a key. Press Esc to cancel.")
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            capture(event, for: target)
            return nil
        }
    }

    private func capture(_ event: NSEvent, for target: ShortcutTarget) {
        guard !event.isARepeat, let flags = event.cgEvent?.flags else { return }
        let keyCode = Int64(event.keyCode)
        let modifiers = flags.intersection(Shortcut.modifiers)
        if keyCode == Int64(kVK_Escape), modifiers.isEmpty {
            stopRecording()
            return
        }
        guard !modifiers.intersection([.maskControl, .maskAlternate, .maskCommand]).isEmpty else {
            message = String(localized: "Include at least one of ⌃, ⌥, or ⌘.")
            return
        }
        let shortcut = Shortcut(keyCode: keyCode, flags: modifiers, key: printableKey(event))
        if Shortcut.unlock.matches(keyCode: keyCode, flags: flags) {
            message = String(localized: "This shortcut is reserved for unlocking.")
            return
        }
        if delegate.shortcut(for: target.other).matches(keyCode: keyCode, flags: flags) {
            message = String(localized: "This shortcut is already in use.")
            return
        }
        delegate.setShortcut(shortcut, for: target)
        stopRecording()
    }

    private func printableKey(_ event: NSEvent) -> String {
        let characters = event.charactersIgnoringModifiers ?? ""
        guard let scalar = characters.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar),
              scalar.properties.generalCategory != .privateUse else { return "" }
        return characters.uppercased()
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
        message = nil
        input.recordingShortcut = false
    }
}
