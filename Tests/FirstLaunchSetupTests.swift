import Darwin
import Foundation
import UserNotifications

@main
struct FirstLaunchSetupTests {
    static func main() {
        var failures = 0
        func expect(_ condition: Bool, _ message: String) {
            if !condition {
                print("FAIL: \(message)")
                failures += 1
            }
        }

        let suite = "FirstLaunchSetupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let newInstall = FirstLaunchSetup.prepare(
            defaults: defaults, accessibilityTrusted: false, notificationStatus: .notDetermined
        )
        expect(newInstall?.requestsAccessibility == true, "A fresh install requests Accessibility")
        expect(newInstall?.offersNotifications == true, "A fresh install offers notifications")
        let nextLaunch = FirstLaunchSetup.prepare(
            defaults: UserDefaults(suiteName: suite)!, accessibilityTrusted: false, notificationStatus: .notDetermined
        )
        expect(nextLaunch == nil, "Skipping or closing doesn't cause another prompt on launch")

        defaults.removePersistentDomain(forName: suite)
        let alreadyTrusted = FirstLaunchSetup.prepare(
            defaults: defaults, accessibilityTrusted: true, notificationStatus: .notDetermined
        )
        expect(alreadyTrusted?.requestsAccessibility == false, "Existing Accessibility permission is respected")
        expect(alreadyTrusted?.offersNotifications == true, "Notifications can still be offered")

        for status: UNAuthorizationStatus in [.authorized, .denied] {
            defaults.removePersistentDomain(forName: suite)
            let onlyAccessibility = FirstLaunchSetup.prepare(
                defaults: defaults, accessibilityTrusted: false, notificationStatus: status
            )
            expect(onlyAccessibility?.requestsAccessibility == true, "Accessibility remains available after a notification choice")
            expect(onlyAccessibility?.offersNotifications == false, "A previous notification choice is respected")
            defaults.removePersistentDomain(forName: suite)
            let alreadySetUp = FirstLaunchSetup.prepare(
                defaults: defaults, accessibilityTrusted: true, notificationStatus: status
            )
            expect(alreadySetUp == nil, "No window appears when both permissions have been addressed")
        }

        if failures != 0 { exit(EXIT_FAILURE) }
        print("First launch setup scenarios passed")
    }
}
