import Foundation

struct TrayCredentials {
    var login: String
    var password: String
    var subscriber: String?
}

enum SettingsStore {
    static let keychainService = "at.yesss.tray.credentials"
    static let keychainAccountPassword = "password"

    private static let loginDefaultsKey = "YesssTray.login"
    private static let subscriberDefaultsKey = "YesssTray.subscriber"

    static var login: String {
        get { UserDefaults.standard.string(forKey: loginDefaultsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: loginDefaultsKey) }
    }

    static var subscriberOverride: String? {
        get {
            let value = UserDefaults.standard.string(forKey: subscriberDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? nil : value
        }
        set {
            UserDefaults.standard.set(newValue ?? "", forKey: subscriberDefaultsKey)
        }
    }

    static func loadCredentials() -> TrayCredentials? {
        let login = self.login.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = KeychainStore().readPassword(service: keychainService, account: keychainAccountPassword) ?? ""
        guard !login.isEmpty, !password.isEmpty else {
            return nil
        }
        return TrayCredentials(login: login, password: password, subscriber: subscriberOverride)
    }

    static func save(login: String, password: String, subscriber: String?) throws {
        self.login = login.trimmingCharacters(in: .whitespacesAndNewlines)
        self.subscriberOverride = subscriber
        if !password.isEmpty {
            try KeychainStore().savePassword(password, service: keychainService, account: keychainAccountPassword)
        }
    }

    static func clearCredentials() {
        login = ""
        subscriberOverride = nil
        KeychainStore().deletePassword(service: keychainService, account: keychainAccountPassword)
    }
}
