import Foundation

enum YesssTrace {
    static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[YesssTray] \(timestamp) \(message)")
        fflush(stdout)
    }

    static func markerSummary(for html: String) -> String {
        let lower = html.lowercased()
        let lines = HtmlTextExtractor.textLines(from: html)
        let available = TextMatch.countLines(containing: "Verfügbar", in: lines)
        let used = TextMatch.countLines(containing: "Verbraucht", in: lines)
        let eu = TextMatch.countLines(containing: "Datenvolumen EU", in: lines)
        let inputs = inputNames(in: html)
        let inputSet = Set(inputs)
        let privacyForm = inputSet.contains("dosave")
            && (inputSet.contains("accept-all") || inputSet.contains("accept-necessary") || inputSet.contains("accept-individual"))
        return [
            "chars=\(html.count)",
            "lines=\(lines.count)",
            "loginForm=\(lower.contains("login_rufnummer") && lower.contains("login_passwort"))",
            "privacyPage=\(privacyForm)",
            "loginFailure=\(lower.contains("login nicht erfolgreich") || lower.contains("login fehlgeschlagen") || lower.contains("rufnummer oder passwort"))",
            "inputs=\(inputs.joined(separator: ","))",
            "verfuegbar=\(available)",
            "verbraucht=\(used)",
            "eu=\(eu)",
        ].joined(separator: " ")
    }

    static func inputNames(in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"<(?:input|button)[^>]+name=[\"']?([^\"'\s>]+)"#, options: [.caseInsensitive]) else {
            return []
        }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        var names: [String] = []
        var seen = Set<String>()
        for match in regex.matches(in: html, range: nsRange) {
            guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: html) else { continue }
            let name = String(html[range])
            if seen.insert(name).inserted {
                names.append(name)
            }
            if names.count >= 12 { break }
        }
        return names
    }
}
