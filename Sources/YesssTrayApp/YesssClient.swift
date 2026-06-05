import Foundation

final class YesssClient {
    private let baseURL: URL
    private let timeout: TimeInterval
    private let cookieStorage: HTTPCookieStorage
    private let session: URLSession
    private var manualCookies: [String: String] = [:]

    init(baseURL: String = "https://login.yesss.at/app/", timeout: TimeInterval = 90) throws {
        guard let url = URL(string: baseURL) else { throw YesssClientError.invalidURL(baseURL) }
        self.baseURL = url
        self.timeout = timeout

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        self.cookieStorage = HTTPCookieStorage()
        configuration.httpCookieStorage = cookieStorage
        self.session = URLSession(configuration: configuration)
        seedConsentCookie()
    }

    func fetch(login username: String, password: String, subscriber: String?) async -> YesssFetchResult {
        let fetchedAt = ISO8601DateFormatter().string(from: Date())
        var warnings: [String] = []
        var diagnostics = YesssDiagnostics()

        do {
            let indexHtml = try await get("index.php")
            diagnostics.indexHtmlLength = indexHtml.count

            try await acceptConsentIfNeeded(pageHtml: indexHtml)
            _ = try await get("index.php")

            let loginHtml = try await performLogin(login: username, password: password)
            diagnostics.loginResponseLength = loginHtml.count
            guard !isLoginFailure(loginHtml) else {
                return YesssFetchResult(authState: .loginRequired, fetchedAt: fetchedAt, expertHtml: "", account: .empty, fallbackQuota: nil, warnings: [], error: "Login was rejected by YESSS. Check the phone number/login and password.", diagnostics: diagnostics)
            }

            let profileHtml = try await get("einstellungen_profil.php")
            diagnostics.profileHtmlLength = profileHtml.count
            let subscriberInfo = SubscriberParser.parse(html: profileHtml)
            warnings.append(contentsOf: subscriberInfo.warnings)

            if let subscriber, !subscriber.isEmpty {
                try await switchSubscriber(subscriber)
            }

            let expertHtml = try await get("kundendaten.php?setmode=expert")
            diagnostics.expertHtmlLength = expertHtml.count
            diagnostics = enrichDiagnostics(diagnostics, expertHtml: expertHtml)

            if isPrivacyPage(expertHtml) {
                return YesssFetchResult(authState: .fetchError, fetchedAt: fetchedAt, expertHtml: "", account: .empty, fallbackQuota: nil, warnings: warnings, error: "YESSS is still showing the privacy/cookie settings page. Consent handling did not complete.", diagnostics: diagnostics)
            }

            if looksLoggedOut(expertHtml) {
                return YesssFetchResult(authState: .loginRequired, fetchedAt: fetchedAt, expertHtml: "", account: .empty, fallbackQuota: nil, warnings: warnings, error: "YESSS returned the login form while loading quota data. The session may have expired or login did not complete.", diagnostics: diagnostics)
            }

            let account = TrayAccount(
                currentSubscriber: subscriberInfo.currentSubscriber ?? subscriber,
                currentLabel: subscriberInfo.currentLabel,
                requiresSubscriberSelection: subscriberInfo.subscribers.count > 1 && subscriberInfo.currentSubscriber == nil && subscriberInfo.currentLabel == nil && subscriber == nil,
                subscriberOptions: subscriberInfo.subscribers
            )

            return YesssFetchResult(authState: .authenticated, fetchedAt: fetchedAt, expertHtml: expertHtml, account: account, fallbackQuota: nil, warnings: warnings, error: nil, diagnostics: diagnostics)
        } catch YesssClientError.loginFailed {
            return YesssFetchResult(authState: .loginRequired, fetchedAt: fetchedAt, expertHtml: "", account: .empty, fallbackQuota: nil, warnings: warnings, error: "Login was rejected by YESSS. Check the phone number/login and password.", diagnostics: diagnostics)
        } catch {
            return YesssFetchResult(authState: .fetchError, fetchedAt: fetchedAt, expertHtml: "", account: .empty, fallbackQuota: nil, warnings: warnings, error: error.localizedDescription, diagnostics: diagnostics)
        }
    }

    func checkCredentials(login username: String, password: String) async -> YesssCredentialCheckResult {
        let trimmedLogin = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLogin.isEmpty, !password.isEmpty else {
            return YesssCredentialCheckResult(isValid: false, message: "Enter login and password first.")
        }

        YesssTrace.log("credential-check start loginLength=\(trimmedLogin.count) passwordLength=\(password.count)")

        do {
            let indexHtml = try await get("index.php")
            YesssTrace.log("credential-check index \(YesssTrace.markerSummary(for: indexHtml))")

            try await acceptConsentIfNeeded(pageHtml: indexHtml)
            _ = try await get("index.php")

            let loginHtml = try await performLogin(login: trimmedLogin, password: password)
            YesssTrace.log("credential-check login-response \(YesssTrace.markerSummary(for: loginHtml))")
            if isLoginFailure(loginHtml) {
                YesssTrace.log("credential-check result invalid reason=login-failure-marker")
                return YesssCredentialCheckResult(isValid: false, message: "Login rejected by YESSS.")
            }

            let protectedHtml = try await get("kundendaten.php?setmode=expert")
            YesssTrace.log("credential-check protected-page \(YesssTrace.markerSummary(for: protectedHtml))")
            if isPrivacyPage(protectedHtml) {
                YesssTrace.log("credential-check result invalid reason=privacy-page")
                return YesssCredentialCheckResult(isValid: false, message: "YESSS is still showing privacy/cookie settings. Consent handling did not complete.")
            }

            if isLoginFailure(protectedHtml) || isLoginForm(protectedHtml) {
                YesssTrace.log("credential-check result invalid reason=protected-page-login-form")
                return YesssCredentialCheckResult(isValid: false, message: "Login rejected by YESSS or no authenticated session was created.")
            }

            guard hasQuotaMarkers(protectedHtml) else {
                YesssTrace.log("credential-check result invalid reason=no-quota-markers")
                return YesssCredentialCheckResult(isValid: false, message: "Login did not reach the quota page. See terminal trace for page markers.")
            }

            YesssTrace.log("credential-check result valid")
            return YesssCredentialCheckResult(isValid: true, message: "Credentials are valid; quota page is reachable.")
        } catch YesssClientError.loginFailed {
            YesssTrace.log("credential-check result invalid reason=loginFailed-exception")
            return YesssCredentialCheckResult(isValid: false, message: "Login rejected by YESSS.")
        } catch {
            YesssTrace.log("credential-check result error message=\(error.localizedDescription)")
            return YesssCredentialCheckResult(isValid: false, message: "Could not check credentials: \(error.localizedDescription)")
        }
    }

    private func seedConsentCookie() {
        let host = baseURL.host ?? "login.yesss.at"
        let consentValue = "{\"categories\":[\"necessary\"]}"
        manualCookies["CookieSettings"] = consentValue

        for path in ["/", "/app", "/app/"] {
            if let cookie = HTTPCookie(properties: [
                .originURL: baseURL.absoluteString,
                .domain: host,
                .path: path,
                .name: "CookieSettings",
                .value: consentValue,
                .secure: "TRUE",
                .version: "0",
            ]) {
                cookieStorage.setCookie(cookie)
            }
        }
        YesssTrace.log("consent-cookie seeded host=\(host) \(cookieSummary())")
    }

    private func enrichDiagnostics(_ diagnostics: YesssDiagnostics, expertHtml: String) -> YesssDiagnostics {
        var result = diagnostics
        let lines = HtmlTextExtractor.textLines(from: expertHtml)
        result.expertTextLineCount = lines.count
        result.availableMarkerCount = TextMatch.countLines(containing: "Verfügbar", in: lines)
        result.usedMarkerCount = TextMatch.countLines(containing: "Verbraucht", in: lines)
        result.euDataMarkerCount = TextMatch.countLines(containing: "Datenvolumen EU", in: lines)
        return result
    }

    private func acceptConsentIfNeeded(pageHtml: String) async throws {
        seedConsentCookie()

        guard isPrivacyPage(pageHtml) else {
            YesssTrace.log("consent-post skipped reason=no-privacy-form")
            return
        }

        // Keep this intentionally identical to the working curl/Python flow.
        // The YESSS privacy form exposes additional checkbox inputs, but posting
        // those back with empty/default values can leave the session stuck on
        // `einstellungen_datenschutz_web.php` in the native URLSession client.
        // Browser/curl submit semantics for the accepted-all button are simply
        // these two fields.
        let fields = [
            ("dosave", "1"),
            ("accept-all", "1"),
        ]

        YesssTrace.log("consent-post fields=\(fields.map { $0.0 }.joined(separator: ","))")
        let body = formEncode(fields)
        _ = try? await post("einstellungen_datenschutz_web.php", body: body, refererPath: "einstellungen_datenschutz_web.php")
        seedConsentCookie()
    }

    private func performLogin(login: String, password: String) async throws -> String {
        let body = formEncode([
            "login_rufnummer": login,
            "login_passwort": password,
        ])
        let html = try await post("index.php", body: body)
        if isLoginFailure(html) {
            throw YesssClientError.loginFailed
        }
        return html
    }

    private func switchSubscriber(_ subscriber: String) async throws {
        let body = formEncode([
            "groupaction": "change_subscriber",
            "subscriber": subscriber,
        ])
        _ = try await post("kundendaten.php", body: body)
    }

    private func get(_ path: String) async throws -> String {
        var request = URLRequest(url: try url(path))
        request.httpMethod = "GET"
        addDefaultHeaders(&request)
        return try await perform(request, path: path)
    }

    private func post(_ path: String, body: Data, refererPath: String? = nil) async throws -> String {
        var request = URLRequest(url: try url(path))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(baseURL.scheme.map { "\($0)://\(baseURL.host ?? "login.yesss.at")" }, forHTTPHeaderField: "Origin")
        if let refererPath {
            request.setValue(try url(refererPath).absoluteString, forHTTPHeaderField: "Referer")
        }
        addDefaultHeaders(&request)
        return try await perform(request, path: path)
    }

    private func perform(_ request: URLRequest, path: String) async throws -> String {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw YesssClientError.transport("Unexpected response")
            }
            storeResponseCookies(from: http)
            let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            YesssTrace.log("request method=\(request.httpMethod ?? "?") path=\(path) status=\(http.statusCode) finalURL=\(http.url?.absoluteString ?? "-") \(YesssTrace.markerSummary(for: html))")
            YesssTrace.log("cookies \(cookieSummary())")
            guard (200..<400).contains(http.statusCode) else {
                throw YesssClientError.requestFailed(http.statusCode, path)
            }
            return html
        } catch let error as YesssClientError {
            throw error
        } catch {
            throw YesssClientError.transport(error.localizedDescription)
        }
    }

    private func url(_ path: String) throws -> URL {
        guard let result = URL(string: path, relativeTo: baseURL) else {
            throw YesssClientError.invalidURL(path)
        }
        return result
    }

    private func cookieSummary() -> String {
        let cookies = cookieStorage.cookies ?? []
        let manualNames = manualCookies.keys.sorted()
        guard !cookies.isEmpty || !manualNames.isEmpty else { return "count=0 manual=0" }

        let descriptions = cookies
            .sorted { lhs, rhs in
                if lhs.name == rhs.name { return lhs.path < rhs.path }
                return lhs.name < rhs.name
            }
            .map { cookie in
                "\(cookie.name)@\(cookie.path)"
            }
        return "count=\(cookies.count) names=\(descriptions.joined(separator: ",")) manual=\(manualNames.count) manualNames=\(manualNames.joined(separator: ","))"
    }

    private func storeResponseCookies(from response: HTTPURLResponse) {
        guard let url = response.url else { return }
        let headerFields = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            guard let key = entry.key as? String else { return }
            result[key] = String(describing: entry.value)
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
        guard !cookies.isEmpty else { return }

        for cookie in cookies {
            manualCookies[cookie.name] = cookie.value
            cookieStorage.setCookie(cookie)
        }
        YesssTrace.log("set-cookie names=\(cookies.map { $0.name }.sorted().joined(separator: ","))")
    }

    private func addDefaultHeaders(_ request: inout URLRequest) {
        request.setValue("Mozilla/5.0 YesssTray/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("de-AT,de;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        if !manualCookies.isEmpty {
            let cookieHeader = manualCookies
                .sorted { $0.key < $1.key }
                .map { key, value in "\(key)=\(value)" }
                .joined(separator: "; ")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
    }

    private func formEncode(_ fields: [String: String]) -> Data {
        let body = fields.map { key, value in
            "\(urlEncode(key))=\(urlEncode(value))"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    private func formEncode(_ fields: [(String, String)]) -> Data {
        let body = fields.map { key, value in
            "\(urlEncode(key))=\(urlEncode(value))"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    private func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func hasQuotaMarkers(_ html: String) -> Bool {
        let lines = HtmlTextExtractor.textLines(from: html)
        return lines.contains { line in
            TextMatch.contains("Verbraucht", in: line)
                || TextMatch.contains("Verfügbar", in: line)
                || TextMatch.contains("Datenvolumen EU", in: line)
        }
    }

    private func isLoginFailure(_ html: String) -> Bool {
        let lower = html.lowercased()
        return lower.contains("login nicht erfolgreich")
            || lower.contains("login fehlgeschlagen")
            || lower.contains("rufnummer oder passwort")
    }

    private func isLoginForm(_ html: String) -> Bool {
        let lower = html.lowercased()
        return lower.contains("login_rufnummer") && lower.contains("login_passwort")
    }

    private func isPrivacyPage(_ html: String) -> Bool {
        let lower = html.lowercased()
        let inputNames = Set(YesssTrace.inputNames(in: html))
        let hasConsentActions = inputNames.contains("accept-all")
            || inputNames.contains("accept-necessary")
            || inputNames.contains("accept-individual")
        let hasConsentForm = inputNames.contains("dosave") && hasConsentActions

        // Authenticated quota pages can contain generic Datenschutz/Cookie links
        // in footer/nav markup. Treat only the actual settings form as privacy
        // blocking; otherwise we falsely reject pages that already contain quota
        // markers after a successful login.
        return hasConsentForm || lower.contains("name=\"accept-all\"") || lower.contains("name='accept-all'")
    }

    private func looksLoggedOut(_ html: String) -> Bool {
        isLoginForm(html)
    }
}
