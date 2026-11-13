import AppKit
import Carbon
import SwiftUI

enum ShortcutTarget: String, CaseIterable, Identifiable {
    case keyboard = "keyboardShortcut"
    case pointer = "pointerShortcut"
    case lockAll = "lockAllShortcut"

    var id: Self { self }
    var title: String {
        switch self {
        case .keyboard: String(localized: "Lock Keyboard")
        case .pointer: String(localized: "Lock Mouse")
        case .lockAll: String(localized: "Lock Everything")
        }
    }

    var defaultShortcut: Shortcut {
        switch self {
        case .keyboard: .keyboard
        case .pointer: .pointer
        case .lockAll: .lockForCurrentLayout()
        }
    }
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
            Section("Automatic Lock") {
                AutomaticLockSettings(delegate: delegate)
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
        .frame(width: 500, height: min(620, (NSScreen.main?.visibleFrame.height ?? 660) - 40))
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
        if ShortcutTarget.allCases.contains(where: {
            $0 != target && delegate.shortcut(for: $0).matches(keyCode: keyCode, flags: flags)
        }) {
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

private struct AutomaticLockSettings: View {
    @ObservedObject var delegate: AppDelegate

    var body: some View {
        Toggle("Lock the keyboard when paws are detected", isOn: Binding(
            get: { delegate.automaticLockEnabled },
            set: { delegate.setAutomaticLockEnabled($0) }
        ))
        trigger("Several keys pressed at once", enabled: \.landingEnabled) {
            threshold("Number of keys", \.landingKeyCount, in: AutomaticLockRules.keyCountRange)
            threshold("Maximum time between presses", \.landingWindowMS, in: AutomaticLockRules.pressWindowRange, step: 5)
        }
        trigger("Several keys held together", enabled: \.settlingEnabled) {
            threshold("Number of keys", \.settlingKeyCount, in: AutomaticLockRules.keyCountRange)
            threshold("Maximum time between presses", \.settlingWindowMS, in: AutomaticLockRules.pressWindowRange, step: 5)
            threshold("Minimum hold time", \.settlingHoldMS, in: AutomaticLockRules.settlingHoldRange, step: 25)
        }
        trigger("Two quick pairs of keys", enabled: \.crossingEnabled) {
            threshold("Maximum time within each pair", \.crossingPairWindowMS, in: AutomaticLockRules.pressWindowRange, step: 5)
            threshold("Minimum overlap within each pair", \.crossingOverlapMS, in: AutomaticLockRules.crossingOverlapRange, step: 5)
            threshold("Maximum time between pairs", \.crossingWindowMS, in: AutomaticLockRules.crossingWindowRange, step: 50)
        }
        trigger("One key held down", enabled: \.singleKeyEnabled) {
            threshold("Minimum hold time", \.singleKeyHoldMS, in: AutomaticLockRules.singleKeyHoldRange, step: 500)
            Text("A long press on any regular key can lock the keyboard. Turn this off in games or apps that use long presses.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        Button("Restore Default Thresholds") {
            var rules = AutomaticLockRules()
            rules.landingEnabled = delegate.automaticLockRules.landingEnabled
            rules.settlingEnabled = delegate.automaticLockRules.settlingEnabled
            rules.crossingEnabled = delegate.automaticLockRules.crossingEnabled
            rules.singleKeyEnabled = delegate.automaticLockRules.singleKeyEnabled
            delegate.setAutomaticLockRules(rules)
        }
        .disabled(!delegate.automaticLockEnabled)
    }

    private func trigger<Content: View>(
        _ title: LocalizedStringKey, enabled: WritableKeyPath<AutomaticLockRules, Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10, content: content)
                .padding(.vertical, 4)
                .disabled(!delegate.automaticLockEnabled)
        } label: {
            HStack(spacing: 12) {
                Text(title)
                Spacer(minLength: 0)
                Toggle(title, isOn: rule(enabled))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!delegate.automaticLockEnabled)
            }
        }
    }

    private func rule<Value>(_ path: WritableKeyPath<AutomaticLockRules, Value>) -> Binding<Value> {
        Binding {
            delegate.automaticLockRules[keyPath: path]
        } set: { value in
            var rules = delegate.automaticLockRules
            rules[keyPath: path] = value
            delegate.setAutomaticLockRules(rules)
        }
    }

    private func threshold(
        _ label: LocalizedStringKey, _ path: WritableKeyPath<AutomaticLockRules, Int>,
        in range: ClosedRange<Int>, step: Int = 1
    ) -> some View {
        let value = delegate.automaticLockRules[keyPath: path]
        return Stepper(value: rule(path), in: range, step: step) {
            LabeledContent {
                if path == \.singleKeyHoldMS {
                    Text(Duration.milliseconds(value), format: .units(
                        allowed: [.seconds], width: .abbreviated,
                        fractionalPart: .show(length: value % 1_000 == 0 ? 0 : 1)
                    ))
                } else if step == 1 {
                    Text(value, format: .number)
                } else {
                    Text(Duration.milliseconds(value), format: .units(allowed: [.milliseconds], width: .abbreviated))
                }
            } label: {
                Text(label)
            }
        }
    }
}
