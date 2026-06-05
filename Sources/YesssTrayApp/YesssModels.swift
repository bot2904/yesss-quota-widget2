import Foundation

enum YesssAuthState {
    case authenticated
    case loginRequired
    case fetchError
}

struct YesssFetchResult {
    var authState: YesssAuthState
    var fetchedAt: String
    var expertHtml: String
    var account: TrayAccount
    var fallbackQuota: TrayQuota?
    var warnings: [String]
    var error: String?
    var diagnostics: YesssDiagnostics
}

struct YesssDiagnostics {
    var indexHtmlLength = 0
    var loginResponseLength = 0
    var profileHtmlLength = 0
    var expertHtmlLength = 0
    var expertTextLineCount = 0
    var availableMarkerCount = 0
    var usedMarkerCount = 0
    var euDataMarkerCount = 0
    var parsedQuotaCount = 0

    var summaryLines: [String] {
        [
            "index_html_length=\(indexHtmlLength)",
            "login_response_length=\(loginResponseLength)",
            "profile_html_length=\(profileHtmlLength)",
            "expert_html_length=\(expertHtmlLength)",
            "expert_text_lines=\(expertTextLineCount)",
            "verfuegbar_markers=\(availableMarkerCount)",
            "verbraucht_markers=\(usedMarkerCount)",
            "eu_data_markers=\(euDataMarkerCount)",
            "parsed_quotas=\(parsedQuotaCount)",
        ]
    }
}

struct YesssCredentialCheckResult {
    var isValid: Bool
    var message: String
}

struct SubscriberParseResult {
    var currentSubscriber: String?
    var currentLabel: String?
    var subscribers: [TraySubscriberOption]
    var warnings: [String]
}

enum YesssClientError: LocalizedError {
    case invalidURL(String)
    case loginFailed
    case requestFailed(Int, String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case let .invalidURL(url):
            return "Invalid YESSS URL: \(url)"
        case .loginFailed:
            return "Login not successful"
        case let .requestFailed(status, path):
            return "YESSS request failed (\(status)): \(path)"
        case let .transport(message):
            return message
        }
    }
}
