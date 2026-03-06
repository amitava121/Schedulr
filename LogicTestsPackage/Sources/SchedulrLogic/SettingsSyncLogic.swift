import Foundation

public enum SettingsSyncLogic {
    public static func shouldApplyRemoteSettings(localUpdatedAt: Date, remoteUpdatedAt: Date?) -> Bool {
        let incomingUpdatedAt = remoteUpdatedAt ?? .distantPast
        return incomingUpdatedAt > localUpdatedAt
    }
}
