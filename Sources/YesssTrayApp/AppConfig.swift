import Foundation

struct RefreshIntervalOption: Equatable {
    let seconds: Int
    let title: String
}

enum AppConfig {
    static let refreshTimeoutSeconds: TimeInterval = 90
    static let defaultPeriodicRefreshSeconds: Int = 60 * 15

    private static let refreshIntervalDefaultsKey = "YesssTray.refreshIntervalSeconds"

    static let refreshIntervalOptions: [RefreshIntervalOption] = [
        RefreshIntervalOption(seconds: 0, title: "Manual only"),
        RefreshIntervalOption(seconds: 60 * 5, title: "Every 5 minutes"),
        RefreshIntervalOption(seconds: 60 * 15, title: "Every 15 minutes"),
        RefreshIntervalOption(seconds: 60 * 30, title: "Every 30 minutes"),
        RefreshIntervalOption(seconds: 60 * 60, title: "Every 1 hour"),
    ]

    static var refreshIntervalSeconds: Int {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: refreshIntervalDefaultsKey) != nil else {
            return defaultPeriodicRefreshSeconds
        }

        let stored = defaults.integer(forKey: refreshIntervalDefaultsKey)
        if refreshIntervalOptions.contains(where: { $0.seconds == stored }) {
            return stored
        }
        return defaultPeriodicRefreshSeconds
    }

    static var periodicRefreshSeconds: TimeInterval {
        TimeInterval(refreshIntervalSeconds)
    }

    static func setRefreshIntervalSeconds(_ seconds: Int) {
        let normalized = refreshIntervalOptions.first(where: { $0.seconds == seconds })?.seconds
            ?? defaultPeriodicRefreshSeconds
        UserDefaults.standard.set(normalized, forKey: refreshIntervalDefaultsKey)
    }

}
