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
}
