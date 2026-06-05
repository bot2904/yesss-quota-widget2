import Foundation

enum RefreshError: LocalizedError {
    case missingCredentials

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Missing YESSS credentials. Open Settings and save your login/password."
        }
    }
}

struct RefreshService {
    func refresh() async throws -> TraySnapshot {
        guard let credentials = SettingsStore.loadCredentials() else {
            throw RefreshError.missingCredentials
        }

        let client = try YesssClient(timeout: AppConfig.refreshTimeoutSeconds)
        let fetch = await client.fetch(
            login: credentials.login,
            password: credentials.password,
            subscriber: credentials.subscriber
        )
        return QuotaParser.buildSnapshot(fetch: fetch)
    }
}
