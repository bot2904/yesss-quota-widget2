import Foundation

enum QuotaParser {
    private static let unitFactors: [String: Int64] = [
        "B": 1,
        "KB": 1024,
        "MB": 1024 * 1024,
        "GB": 1024 * 1024 * 1024,
        "TB": 1024 * 1024 * 1024 * 1024,
    ]

    static func buildSnapshot(fetch: YesssFetchResult) -> TraySnapshot {
        var snapshot = TraySnapshot.empty
        var diagnostics = fetch.diagnostics
        snapshot.generatedAt = ISO8601DateFormatter().string(from: Date())
        snapshot.updatedAt = fetch.fetchedAt
        snapshot.account = fetch.account
        snapshot.warnings = fetch.warnings

        switch fetch.authState {
        case .loginRequired:
            snapshot.status = .loginRequired
            snapshot.message = fetch.error ?? "Login required"
            snapshot.menuTitle = nil
            return snapshot
        case .fetchError:
            snapshot.status = .error
            snapshot.message = fetch.error ?? "Refresh failed"
            snapshot.menuTitle = nil
            return snapshot
        case .authenticated:
            break
        }

        if fetch.account.requiresSubscriberSelection {
            snapshot.status = .subscriberSelectionRequired
            snapshot.message = "Please select a phone number"
            snapshot.menuTitle = nil
            return snapshot
        }

        let lines = HtmlTextExtractor.textLines(from: fetch.expertHtml)
        var quotas = extractProgressQuotas(lines: lines)
        quotas.append(contentsOf: extractEUDataQuota(lines: lines, existingCount: quotas.count))

        if quotas.isEmpty, let fallback = fetch.fallbackQuota {
            quotas.append(fallback)
        }

        quotas = deduplicate(quotas)
        diagnostics.parsedQuotaCount = quotas.count
        let validUntil = parseValidUntil(lines: lines)
        let resetDay = parseBillingResetDay(lines: lines)
        let resetAt = nextResetTimestamp(fetchedAt: fetch.fetchedAt, resetDay: resetDay, validUntil: validUntil)
        for idx in quotas.indices {
            quotas[idx].validUntil = validUntil
            quotas[idx].resetAt = resetAt
        }

        snapshot.quotas = quotas
        snapshot.primaryQuota = selectPrimaryQuota(quotas)
        if let remaining = snapshot.primaryQuota?.remainingBytes {
            snapshot.menuTitle = formatMenuTitle(bytes: remaining)
        }

        if quotas.isEmpty {
            snapshot.status = .dataUnavailable
            snapshot.message = "Quota data unavailable. Fetched expert page (\(diagnostics.expertHtmlLength) chars, \(diagnostics.expertTextLineCount) text lines), but found no quota rows. Markers: Verfügbar=\(diagnostics.availableMarkerCount), Verbraucht=\(diagnostics.usedMarkerCount), EU=\(diagnostics.euDataMarkerCount)."
            snapshot.warnings.append(contentsOf: diagnostics.summaryLines)
        } else {
            snapshot.status = .ok
            snapshot.message = "Quota updated (\(quotas.count) quota item\(quotas.count == 1 ? "" : "s"))"
        }
        return snapshot
    }

    static func extractProgressQuotas(lines: [String]) -> [TrayQuota] {
        var items: [TrayQuota] = []
        var pendingAvailable: (Double, String?)?

        for (lineIndex, line) in lines.enumerated() {
            if let available = TextMatch.first(pattern: "^Verf(?:u|ü)gbar:\\s*(.+)$", in: line), available.count > 1 {
                pendingAvailable = parseInlineQuantity(String(available[1]))
                continue
            }

            guard let match = TextMatch.first(
                pattern: "^Verbraucht:\\s*([0-9][0-9.,]*)\\s*([A-Za-zÄÖÜäöüß/]+)?\\s*\\(von\\s*([0-9][0-9.,]*)\\s*([^)]+?)\\)\\s*$",
                in: line
            ), match.count > 4 else {
                continue
            }

            guard let used = parseDENumber(match[1]), let total = parseDENumber(match[3]) else {
                pendingAvailable = nil
                continue
            }

            let heading = inferHeading(lines: lines, index: lineIndex)
            let unit = normalizeUnit(match[4].isEmpty ? match[2] : match[4])
            let remaining = pendingAvailable?.0 ?? max(total - used, 0)
            items.append(makeQuotaItem(index: items.count + 1, title: heading, category: classifyHeading(heading), unit: unit, remaining: remaining, total: total, used: used))
            pendingAvailable = nil
        }

        return items
    }

    static func extractEUDataQuota(lines: [String], existingCount: Int) -> [TrayQuota] {
        var items: [TrayQuota] = []
        let pattern = "Datenvolumen\\s*EU\\s*verbleibend:\\s*([0-9][0-9.,]*)\\s*([KMGTP]?B)\\s*von\\s*([0-9][0-9.,]*)\\s*([KMGTP]?B)"
        for line in lines {
            guard let match = TextMatch.first(pattern: pattern, in: line), match.count > 4,
                  let remaining = parseDENumber(match[1]), let total = parseDENumber(match[3]) else { continue }
            let unit = normalizeUnit(match[4].isEmpty ? match[2] : match[4])
            items.append(makeQuotaItem(index: existingCount + items.count + 1, title: "Datenvolumen EU", category: "eu_data", unit: unit, remaining: remaining, total: total, used: max(total - remaining, 0)))
        }
        return items
    }

    static func selectPrimaryQuota(_ items: [TrayQuota]) -> TrayQuota? {
        let nonEUData = items.filter { $0.category == "data" && !$0.title.localizedCaseInsensitiveContains("eu") }
        if let item = nonEUData.max(by: { ($0.totalBytes ?? 0) < ($1.totalBytes ?? 0) }) { return item }
        let data = items.filter { $0.category == "data" }
        if let item = data.max(by: { ($0.totalBytes ?? 0) < ($1.totalBytes ?? 0) }) { return item }
        let byteItems = items.filter { $0.remainingBytes != nil }
        if let item = byteItems.max(by: { ($0.totalBytes ?? 0) < ($1.totalBytes ?? 0) }) { return item }
        return items.first
    }

    private static func makeQuotaItem(index: Int, title: String, category: String, unit: String?, remaining: Double, total: Double, used: Double) -> TrayQuota {
        let remainingBytes = asBytes(value: remaining, unit: unit)
        let totalBytes = asBytes(value: total, unit: unit)
        let usedBytes = asBytes(value: used, unit: unit)
        let percentUsed = total > 0 ? round((used / total) * 10_000) / 100 : nil

        return TrayQuota(
            id: "\(slugify(title))-\(index)",
            title: title,
            category: category,
            unitKind: remainingBytes != nil && totalBytes != nil ? "bytes" : "count",
            unit: unit,
            remainingValue: displayValue(remaining),
            totalValue: displayValue(total),
            usedValue: displayValue(used),
            remainingBytes: remainingBytes,
            totalBytes: totalBytes,
            usedBytes: usedBytes,
            percentUsed: percentUsed,
            remainingHuman: remainingBytes.map(formatBytesHuman),
            totalHuman: totalBytes.map(formatBytesHuman),
            validUntil: nil,
            resetAt: nil
        )
    }

    private static func inferHeading(lines: [String], index: Int) -> String {
        let skipPrefixes = ["verfügbar:", "verfugbar:", "verbraucht:", "bis zur warnung", "details"]
        guard index > 0 else { return "Unbekannt" }
        for i in stride(from: index - 1, through: max(0, index - 7), by: -1) {
            let candidate = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            let lowered = candidate.lowercased()
            if skipPrefixes.contains(where: { lowered.hasPrefix($0) }) { continue }
            if !candidate.isEmpty { return candidate.trimmingCharacters(in: CharacterSet(charactersIn: ":")) }
        }
        return "Unbekannt"
    }

    private static func classifyHeading(_ heading: String) -> String {
        let lowered = heading.lowercased()
        if lowered.contains("datenvolumen") && lowered.contains("eu") { return "eu_data" }
        if lowered.contains("datenvolumen") { return "data" }
        if lowered.contains("minute") || lowered.contains("sms") { return "minutes_sms" }
        return "other"
    }

    private static func deduplicate(_ items: [TrayQuota]) -> [TrayQuota] {
        var seen = Set<String>()
        var out: [TrayQuota] = []
        for item in items {
            let key = [item.title.lowercased(), item.category, String(item.remainingBytes ?? -1), String(item.totalBytes ?? -1), String(item.remainingValue ?? -1), String(item.totalValue ?? -1)].joined(separator: "|")
            if seen.insert(key).inserted { out.append(item) }
        }
        let order = ["data": 0, "eu_data": 1, "minutes_sms": 2, "other": 3]
        return out.sorted { (order[$0.category] ?? 9, $0.title) < (order[$1.category] ?? 9, $1.title) }
    }

    private static func parseValidUntil(lines: [String]) -> String? {
        for line in lines {
            guard let match = TextMatch.first(pattern: "g(?:u|ü)ltig\\s+bis:\\s*(\\d{1,2}\\.\\d{1,2}\\.\\d{2,4})(?:\\s+(\\d{1,2}:\\d{2}))?", in: line), match.count > 1 else { continue }
            let parts = match[1].split(separator: ".").compactMap { Int($0) }
            guard parts.count == 3 else { continue }
            let year = parts[2] < 100 ? parts[2] + 2000 : parts[2]
            let timeParts = (match.count > 2 && !match[2].isEmpty ? match[2] : "23:59").split(separator: ":").compactMap { Int($0) }
            guard timeParts.count == 2 else { continue }
            var components = DateComponents()
            components.timeZone = TimeZone(identifier: "Europe/Vienna")
            components.year = year
            components.month = parts[1]
            components.day = parts[0]
            components.hour = timeParts[0]
            components.minute = timeParts[1]
            if let date = Calendar(identifier: .gregorian).date(from: components) {
                return isoWithMinutes(date)
            }
        }
        return nil
    }

    private static func parseBillingResetDay(lines: [String]) -> Int? {
        for line in lines {
            guard let match = TextMatch.first(pattern: "abrechnungszeitraum\\s+immer\\s+vom\\s+(\\d{1,2})\\.\\s+bis\\s+zum\\s+(\\d{1,2})\\.", in: line), match.count > 1 else { continue }
            if let day = Int(match[1]), (1...31).contains(day) { return day }
        }
        return nil
    }

    private static func nextResetTimestamp(fetchedAt: String?, resetDay: Int?, validUntil: String?) -> String? {
        let localTZ = TimeZone(identifier: "Europe/Vienna") ?? .current
        let now = SnapshotDateParser.parse(fetchedAt) ?? Date()
        let calendar = Calendar(identifier: .gregorian)
        var localCalendar = calendar
        localCalendar.timeZone = localTZ

        if let resetDay {
            var components = localCalendar.dateComponents([.year, .month], from: now)
            components.day = min(resetDay, daysInMonth(year: components.year ?? 2000, month: components.month ?? 1))
            components.hour = 0
            components.minute = 0
            components.timeZone = localTZ
            var candidate = localCalendar.date(from: components) ?? now
            if now >= candidate {
                components.month = (components.month ?? 1) + 1
                if components.month == 13 {
                    components.month = 1
                    components.year = (components.year ?? 2000) + 1
                }
                components.day = min(resetDay, daysInMonth(year: components.year ?? 2000, month: components.month ?? 1))
                candidate = localCalendar.date(from: components) ?? now
            }
            return isoWithMinutes(candidate)
        }

        if let validDate = SnapshotDateParser.parse(validUntil) {
            return isoWithMinutes(validDate.addingTimeInterval(60))
        }
        return nil
    }

    private static func parseInlineQuantity(_ raw: String) -> (Double, String?)? {
        guard let match = TextMatch.first(pattern: "([0-9][0-9.,]*)\\s*([A-Za-zÄÖÜäöüß/]+)?", in: raw), match.count > 1,
              let value = parseDENumber(match[1]) else { return nil }
        let unit = match.count > 2 ? normalizeUnit(match[2]) : nil
        return (value, unit)
    }

    private static func parseDENumber(_ raw: String) -> Double? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
        s = s.replacingOccurrences(of: "\u{00a0}", with: "")
        if s.contains(",") && s.contains(".") {
            if (s.range(of: ",", options: .backwards)?.lowerBound ?? s.startIndex) > (s.range(of: ".", options: .backwards)?.lowerBound ?? s.startIndex) {
                s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                s = s.replacingOccurrences(of: ",", with: "")
            }
        } else if s.contains(",") {
            s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        }
        return Double(s)
    }

    private static func normalizeUnit(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let upper = trimmed.uppercased()
        if unitFactors[upper] != nil { return upper }
        if ["MINUTEN", "SMS", "MINUTE", "MINUTES", "MIN/SMS", "MINUTEN/SMS"].contains(upper) { return "Minuten/SMS" }
        return trimmed
    }

    private static func asBytes(value: Double, unit: String?) -> Int64? {
        guard let unit, let factor = unitFactors[unit.uppercased()] else { return nil }
        return Int64((value * Double(factor)).rounded())
    }

    private static func formatBytesHuman(_ bytes: Int64) -> String {
        let gb = Double(unitFactors["GB"]!)
        let mb = Double(unitFactors["MB"]!)
        if Double(bytes) >= gb { return "\((Double(bytes) / gb * 100).rounded() / 100) GB" }
        return "\((Double(bytes) / mb * 10).rounded() / 10) MB"
    }

    private static func formatMenuTitle(bytes: Int64) -> String {
        let gb = Double(bytes) / Double(unitFactors["GB"]!)
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return String(format: "%.0f MB", Double(bytes) / Double(unitFactors["MB"]!))
    }

    private static func displayValue(_ value: Double) -> Double {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.001 { return rounded }
        return (value * 1000).rounded() / 1000
    }

    private static func slugify(_ value: String) -> String {
        let lowered = value.lowercased()
        let slug = lowered.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "quota" : slug
    }


    private static func daysInMonth(year: Int, month: Int) -> Int {
        var components = DateComponents()
        components.year = year
        components.month = month
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: components) ?? Date()
        return calendar.range(of: .day, in: .month, for: date)?.count ?? 28
    }

    private static func isoWithMinutes(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        return formatter.string(from: date)
    }
}
