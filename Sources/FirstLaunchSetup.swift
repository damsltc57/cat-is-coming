import Foundation
import UserNotifications

struct FirstLaunchSetup {
    let requestsAccessibility: Bool
    let offersNotifications: Bool

    static func prepare(
        defaults: UserDefaults, accessibilityTrusted: Bool, notificationStatus: UNAuthorizationStatus
    ) -> Self? {
        let key = "hasShownFirstLaunchSetup"
        guard !defaults.bool(forKey: key) else { return nil }
        defaults.set(true, forKey: key)

        let offersNotifications = notificationStatus == .notDetermined
        guard !accessibilityTrusted || offersNotifications else { return nil }
        return Self(requestsAccessibility: !accessibilityTrusted, offersNotifications: offersNotifications)
    }
}
