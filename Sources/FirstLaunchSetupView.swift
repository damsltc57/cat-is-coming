import SwiftUI

struct FirstLaunchSetupView: View {
    @ObservedObject var input: InputLock
    let setup: FirstLaunchSetup
    let enableNotifications: () async -> Bool
    let close: () -> Void
    @State private var requestingNotifications = false
    @State private var notificationRequestFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image("CatArtwork")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Cat Is Coming")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Find the cat in your menu bar.")
                        .foregroundStyle(.secondary)
                }
            }

            if setup.requestsAccessibility {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Label("Accessibility", systemImage: "keyboard")
                        .font(.headline)
                    Text("Allow Accessibility in System Settings so Cat Is Coming can lock your keyboard and mouse.")
                        .foregroundStyle(.secondary)
                    if input.ready {
                        Label("Keyboard and mouse locking is ready.", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Open Accessibility Settings…") { input.openAccessibilitySettings() }
                        if input.accessibilityTrusted, let issue = input.issue {
                            Text(issue).foregroundStyle(.secondary)
                            Button("Try Again") { input.refresh() }
                        }
                    }
                }
            }

            if setup.offersNotifications {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Label("Notifications (optional)", systemImage: "bell")
                        .font(.headline)
                    Text("Get a macOS banner after using an unlock shortcut. You can turn this on later in Settings.")
                        .foregroundStyle(.secondary)
                    if notificationRequestFailed {
                        Text("Couldn’t enable notifications. Try again or skip this step.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Spacer()
                if setup.offersNotifications {
                    Button("Not Now", action: close)
                        .keyboardShortcut(.cancelAction)
                    Button("Allow Notifications…", action: requestNotifications)
                        .buttonStyle(.borderedProminent)
                        .disabled(requestingNotifications)
                } else {
                    Button("Done", action: close)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func requestNotifications() {
        requestingNotifications = true
        notificationRequestFailed = false
        Task {
            if await enableNotifications() {
                close()
            } else {
                notificationRequestFailed = true
            }
            requestingNotifications = false
        }
    }
}
