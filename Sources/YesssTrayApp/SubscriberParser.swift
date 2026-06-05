import Foundation

enum SubscriberParser {
    static func parse(html: String) -> SubscriberParseResult {
        let subscribers = extractSubscriberOptions(html: html)
        let currentDisplay = extractCurrentDisplay(html: html)
        var warnings: [String] = []
        if !subscribers.isEmpty && currentDisplay == nil {
            warnings.append("current_subscriber_unknown")
        }
        return SubscriberParseResult(
            currentSubscriber: nil,
            currentLabel: currentDisplay,
            subscribers: subscribers,
            warnings: warnings
        )
    }

    private static func extractSubscriberOptions(html: String) -> [TraySubscriberOption] {
        var options: [TraySubscriberOption] = []
        var seen = Set<String>()
        let pattern = #"subscriber=([^&"'<>\s]+)[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: nsRange) {
            guard match.numberOfRanges > 2,
                  let idRange = Range(match.range(at: 1), in: html),
                  let labelRange = Range(match.range(at: 2), in: html) else { continue }
            let id = String(html[idRange]).removingPercentEncoding ?? String(html[idRange])
            guard seen.insert(id).inserted else { continue }
            let labelHtml = String(html[labelRange])
            let label = HtmlTextExtractor.plainText(from: labelHtml).replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            options.append(TraySubscriberOption(id: id, label: label.isEmpty ? id : label))
        }
        return options
    }

    private static func extractCurrentDisplay(html: String) -> String? {
        let lines = HtmlTextExtractor.textLines(from: html)
        for (idx, line) in lines.enumerated() {
            let lower = line.lowercased()
            if lower == "admin" || lower.contains("admin") {
                if let phone = nearbyPhone(lines: lines, around: idx) {
                    return "\(line) \(phone)"
                }
                return line
            }
        }
        return nearbyPhone(lines: lines, around: 0)
    }

    private static func nearbyPhone(lines: [String], around index: Int) -> String? {
        let start = max(0, index - 4)
        let end = min(lines.count - 1, index + 8)
        guard start <= end else { return nil }
        for i in start...end {
            if let match = TextMatch.first(pattern: #"(?:\+43|0)\s?\d[\d\s/.-]{5,}"#, in: lines[i]) {
                return match[0]
            }
        }
        return nil
    }

}
