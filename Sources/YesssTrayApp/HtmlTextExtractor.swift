import Foundation

enum HtmlTextExtractor {
    static func textLines(from html: String) -> [String] {
        var text = html
        text = text.replacingOccurrences(of: "(?is)<script[^>]*>.*?</script>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?is)<style[^>]*>.*?</style>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(
            of: "(?i)</(p|div|li|tr|td|th|h1|h2|h3|h4|h5|h6|section|article)>",
            with: "\n",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = decodeEntities(text)

        return text.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func plainText(from html: String) -> String {
        textLines(from: html).joined(separator: "\n")
    }

    private static func decodeEntities(_ value: String) -> String {
        var result = value
        let named: [String: String] = [
            "&nbsp;": " ", "&#160;": " ",
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'",
            "&auml;": "ä", "&Auml;": "Ä", "&ouml;": "ö", "&Ouml;": "Ö", "&uuml;": "ü", "&Uuml;": "Ü", "&szlig;": "ß",
        ]
        for (entity, replacement) in named {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        result = result.replacingOccurrences(of: "&#(\\d+);", with: { match in
            guard let code = Int(match.dropFirst(2).dropLast()), let scalar = UnicodeScalar(code) else { return String(match) }
            return String(Character(scalar))
        })
        return result
    }
}

private extension String {
    func replacingOccurrences(of pattern: String, with transform: (Substring) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        let nsRange = NSRange(startIndex..<endIndex, in: self)
        let matches = regex.matches(in: self, range: nsRange).reversed()
        var output = self
        for match in matches {
            guard let range = Range(match.range, in: output) else { continue }
            output.replaceSubrange(range, with: transform(output[range]))
        }
        return output
    }
}
