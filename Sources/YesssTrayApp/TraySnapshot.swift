import Foundation

enum TraySnapshotStatus: String, Codable, Equatable {
    case ok
    case loginRequired = "login_required"
    case subscriberSelectionRequired = "subscriber_selection_required"
    case dataUnavailable = "data_unavailable"
    case error

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? "error"
        self = TraySnapshotStatus(rawValue: raw) ?? .error
    }
}

struct TraySnapshot: Codable {
    var modelVersion: String
    var generatedAt: String?
    var status: TraySnapshotStatus
    var message: String
    var updatedAt: String?
    var menuTitle: String?
    var account: TrayAccount
    var primaryQuota: TrayQuota?
    var quotas: [TrayQuota]
    var warnings: [String]

    static let empty = TraySnapshot(
        modelVersion: "yesss.tray_snapshot.v1",
        generatedAt: nil,
        status: .dataUnavailable,
        message: "No data yet",
        updatedAt: nil,
        menuTitle: nil,
        account: .empty,
        primaryQuota: nil,
        quotas: [],
        warnings: []
    )
}

struct TrayAccount: Codable {
    var currentSubscriber: String?
    var currentLabel: String?
    var requiresSubscriberSelection: Bool
    var subscriberOptions: [TraySubscriberOption]

    static let empty = TrayAccount(
        currentSubscriber: nil,
        currentLabel: nil,
        requiresSubscriberSelection: false,
        subscriberOptions: []
    )
}

struct TraySubscriberOption: Codable, Identifiable {
    var id: String
    var label: String
}

struct TrayQuota: Codable, Identifiable {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    var id: String
    var title: String
    var category: String
    var unitKind: String
    var unit: String?
    var remainingValue: Double?
    var totalValue: Double?
    var usedValue: Double?
    var remainingBytes: Int64?
    var totalBytes: Int64?
    var usedBytes: Int64?
    var percentUsed: Double?
    var remainingHuman: String?
    var totalHuman: String?
    var validUntil: String?
    var resetAt: String?

    var progress: Double? {
        if let percentUsed {
            return max(0, min(1, percentUsed / 100.0))
        }
        if let usedValue, let totalValue, totalValue > 0 {
            return max(0, min(1, usedValue / totalValue))
        }
        return nil
    }

    var remainingDisplay: String {
        if let remainingHuman {
            return remainingHuman
        }
        if let remainingValue {
            let value = remainingValue.rounded() == remainingValue ? "\(Int(remainingValue))" : String(format: "%.2f", remainingValue)
            return [value, unit ?? ""].joined(separator: " ").trimmingCharacters(in: .whitespaces)
        }
        return "-"
    }

    var totalDisplay: String {
        if let totalHuman {
            return totalHuman
        }
        if let totalValue {
            let value = totalValue.rounded() == totalValue ? "\(Int(totalValue))" : String(format: "%.2f", totalValue)
            return [value, unit ?? ""].joined(separator: " ").trimmingCharacters(in: .whitespaces)
        }
        return "-"
    }

    var usedDisplay: String {
        if let usedBytes {
            return Self.byteFormatter.string(fromByteCount: usedBytes)
        }
        if let usedValue {
            let value = usedValue.rounded() == usedValue ? "\(Int(usedValue))" : String(format: "%.2f", usedValue)
            return [value, unit ?? ""].joined(separator: " ").trimmingCharacters(in: .whitespaces)
        }
        return "-"
    }

    var resetDate: Date? {
        SnapshotDateParser.parse(resetAt)
    }

    var validUntilDate: Date? {
        SnapshotDateParser.parse(validUntil)
    }
}

enum SnapshotDateParser {
    private static let formatters: [ISO8601DateFormatter] = {
        let base = ISO8601DateFormatter()
        base.formatOptions = [.withInternetDateTime]

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return [fractional, base]
    }()

    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else {
            return nil
        }

        for formatter in formatters {
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }
}
