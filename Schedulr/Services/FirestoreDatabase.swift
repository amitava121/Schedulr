import Foundation
import FirebaseCore
import FirebaseFirestore

/// Resolves the app's configured Firestore database. Every `Firestore` instance must come
/// from here: plain `Firestore.firestore()` silently targets `(default)`, which does not
/// exist in this project — the configured database is `schedulr`.
enum FirestoreDatabase {
    private static let infoKey = "FIRESTORE_DATABASE_ID"
    private static let legacyInfoKey = "FirestoreDatabaseID"

    static var configuredID: String? {
        let primary = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String
        let legacy = Bundle.main.object(forInfoDictionaryKey: legacyInfoKey) as? String
        let raw = (primary ?? legacy)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }
        if raw == "(default)" || raw.caseInsensitiveCompare("default") == .orderedSame {
            return nil
        }
        return raw
    }

    static func firestore() -> Firestore {
        guard let app = FirebaseApp.app() else { return Firestore.firestore() }
        if let configuredID {
            return Firestore.firestore(app: app, database: configuredID)
        }
        return Firestore.firestore(app: app)
    }

    /// Firestore rejects dates outside 0001-01-01...9999-12-31 ('Invalid timestamp').
    static let validDateRange =
        Date(timeIntervalSince1970: -62_135_596_800)...Date(timeIntervalSince1970: 253_402_300_799)

    /// `Timestamp` for `date`, or `NSNull` when it is nil or outside Firestore's range
    /// (e.g. `Date.distantPast`), which would otherwise crash `setData` encoding.
    static func timestampOrNull(_ date: Date?) -> Any {
        guard let date, validDateRange.contains(date) else { return NSNull() }
        return Timestamp(date: date)
    }

    static func timestamps(_ dates: [Date]) -> [Timestamp] {
        dates.filter { validDateRange.contains($0) }.map { Timestamp(date: $0) }
    }
}
