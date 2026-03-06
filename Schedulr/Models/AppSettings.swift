import Foundation
import SwiftUI

extension Notification.Name {
    static let accentColorDidChange = Notification.Name("AppSettings.accentColorDidChange")
}

enum TimeFormatPreference: String, CaseIterable, Identifiable {
    case system
    case twelveHour
    case twentyFourHour

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System Default"
        case .twelveHour:
            return "12-hour"
        case .twentyFourHour:
            return "24-hour"
        }
    }
}

enum AlternativeCalendarOption: String, CaseIterable, Identifiable {
    case bangla
    case buddhist
    case chinese
    case coptic
    case ethiopicAmeteMihret
    case ethiopicAmeteAlem
    case hebrew
    case indian
    case islamic
    case islamicCivil
    case islamicTabular
    case islamicUmmAlQura
    case japanese
    case persian
    case republicOfChina

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bangla: return "Bangla"
        case .buddhist: return "Buddhist"
        case .chinese: return "Chinese"
        case .coptic: return "Coptic"
        case .ethiopicAmeteMihret: return "Ethiopic (Amete Mihret)"
        case .ethiopicAmeteAlem: return "Ethiopic (Amete Alem)"
        case .hebrew: return "Hebrew"
        case .indian: return "Indian National"
        case .islamic: return "Islamic"
        case .islamicCivil: return "Islamic Civil"
        case .islamicTabular: return "Islamic Tabular"
        case .islamicUmmAlQura: return "Islamic Umm al-Qura"
        case .japanese: return "Japanese"
        case .persian: return "Persian"
        case .republicOfChina: return "Republic of China"
        }
    }

    var calendarIdentifier: Calendar.Identifier? {
        switch self {
        case .bangla:
            return nil
        case .buddhist:
            return .buddhist
        case .chinese:
            return .chinese
        case .coptic:
            return .coptic
        case .ethiopicAmeteMihret:
            return .ethiopicAmeteMihret
        case .ethiopicAmeteAlem:
            return .ethiopicAmeteAlem
        case .hebrew:
            return .hebrew
        case .indian:
            return .indian
        case .islamic:
            return .islamic
        case .islamicCivil:
            return .islamicCivil
        case .islamicTabular:
            return .islamicTabular
        case .islamicUmmAlQura:
            return .islamicUmmAlQura
        case .japanese:
            return .japanese
        case .persian:
            return .persian
        case .republicOfChina:
            return .republicOfChina
        }
    }
}

/// Global app-wide settings stored in UserDefaults.
/// All settings have sensible defaults and persist across launches.
@Observable
final class AppSettings {
    static let shared = AppSettings()
    static let defaultAccentColorHex = "#4F9FF8"

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let defaultAlertStyle = "settings.defaultAlertStyle"
        static let defaultSnoozeDuration = "settings.defaultSnoozeDuration"
        static let defaultEarlyReminder = "settings.defaultEarlyReminder"
        static let defaultRepeatPattern = "settings.defaultRepeatPattern"
        static let defaultPriority = "settings.defaultPriority"
        static let defaultCalendar = "settings.defaultCalendar"
        static let hotNaturalLanguageEnabled = "settings.hotNaturalLanguageEnabled"
        static let firstDayOfWeek = "settings.firstDayOfWeek"
        static let use24HourTime = "settings.use24HourTime"
        static let timeFormatMode = "settings.timeFormatMode"
        static let accentColorHex = "settings.accentColorHex"
        static let appearanceMode = "settings.appearanceMode"
        static let hapticFeedbackEnabled = "settings.hapticFeedbackEnabled"
        static let notificationBadgeEnabled = "settings.notificationBadgeEnabled"
        static let autoSyncOnLaunch = "settings.autoSyncOnLaunch"
        static let showBanglaDate = "settings.showBanglaDate"
        static let alternativeCalendarOption = "settings.alternativeCalendarOption"
        static let defaultTimeZoneOverride = "settings.defaultTimeZoneOverride"
        static let conflictDetectionEnabled = "settings.conflictDetectionEnabled"
        static let suppressNotificationsDuringFocus = "settings.suppressNotificationsDuringFocus"
        static let dailyDigestEnabled = "settings.dailyDigestEnabled"
        static let dailyDigestHour = "settings.dailyDigestHour"
        static let dailyDigestMinute = "settings.dailyDigestMinute"
        static let settingsUpdatedAt = "settings.settingsUpdatedAt"
    }

    private var suppressSettingsUpdatedAtWrites = false

    private enum LegacyKeys {
        static let timelineStartHour = "settings.timelineStartHour"
        static let timelineEndHour = "settings.timelineEndHour"
        static let preferredAppIconName = "settings.preferredAppIconName"
    }

    // MARK: - Alert & Notification Defaults

    var defaultAlertStyle: AlertDeliveryOption {
        didSet {
            defaults.set(defaultAlertStyle.rawValue, forKey: Keys.defaultAlertStyle)
            touchSettingsUpdatedAt()
        }
    }

    var defaultSnoozeDuration: Int {
        didSet {
            let clamped = max(1, min(defaultSnoozeDuration, 60))
            if defaultSnoozeDuration != clamped {
                defaultSnoozeDuration = clamped
                return
            }
            defaults.set(defaultSnoozeDuration, forKey: Keys.defaultSnoozeDuration)
            touchSettingsUpdatedAt()
        }
    }

    var defaultEarlyReminderMinutes: Int {
        didSet {
            let clamped = max(0, defaultEarlyReminderMinutes)
            if defaultEarlyReminderMinutes != clamped {
                defaultEarlyReminderMinutes = clamped
                return
            }
            defaults.set(defaultEarlyReminderMinutes, forKey: Keys.defaultEarlyReminder)
            touchSettingsUpdatedAt()
        }
    }

    // MARK: - Schedule Defaults

    var defaultRepeatPattern: RepeatPattern {
        didSet {
            defaults.set(defaultRepeatPattern.rawValue, forKey: Keys.defaultRepeatPattern)
            touchSettingsUpdatedAt()
        }
    }

    var defaultPriority: SchedulePriority {
        didSet {
            defaults.set(defaultPriority.rawValue, forKey: Keys.defaultPriority)
            touchSettingsUpdatedAt()
        }
    }

    var defaultCalendar: String {
        didSet {
            defaults.set(defaultCalendar, forKey: Keys.defaultCalendar)
            touchSettingsUpdatedAt()
        }
    }

    var hotNaturalLanguageEnabled: Bool {
        didSet {
            defaults.set(hotNaturalLanguageEnabled, forKey: Keys.hotNaturalLanguageEnabled)
            touchSettingsUpdatedAt()
        }
    }

    // MARK: - Calendar & Timeline

    var firstDayOfWeek: Int {
        didSet {
            let clamped = max(1, min(firstDayOfWeek, 7))
            if firstDayOfWeek != clamped {
                firstDayOfWeek = clamped
                return
            }
            defaults.set(firstDayOfWeek, forKey: Keys.firstDayOfWeek)
            touchSettingsUpdatedAt()
        }
    }

    var timeFormatPreference: TimeFormatPreference {
        didSet {
            defaults.set(timeFormatPreference.rawValue, forKey: Keys.timeFormatMode)
            switch timeFormatPreference {
            case .system:
                defaults.removeObject(forKey: Keys.use24HourTime)
            case .twelveHour:
                defaults.set(false, forKey: Keys.use24HourTime)
            case .twentyFourHour:
                defaults.set(true, forKey: Keys.use24HourTime)
            }
            touchSettingsUpdatedAt()
        }
    }

    var use24HourTime: Bool? {
        get {
            switch timeFormatPreference {
            case .system:
                return nil
            case .twelveHour:
                return false
            case .twentyFourHour:
                return true
            }
        }
        set {
            if let v = newValue {
                timeFormatPreference = v ? .twentyFourHour : .twelveHour
            } else {
                timeFormatPreference = .system
            }
        }
    }

    // MARK: - Appearance

    var accentColorHex: String {
        didSet {
            defaults.set(accentColorHex, forKey: Keys.accentColorHex)
            if oldValue.caseInsensitiveCompare(accentColorHex) != .orderedSame {
                NotificationCenter.default.post(name: .accentColorDidChange, object: nil)
            }
            touchSettingsUpdatedAt()
        }
    }

    var accentColor: Color {
        Color(hex: accentColorHex) ?? Color(red: 0.31, green: 0.62, blue: 0.97)
    }

    /// 0 = System, 1 = Light, 2 = Dark
    var appearanceMode: Int {
        didSet {
            defaults.set(appearanceMode, forKey: Keys.appearanceMode)
            touchSettingsUpdatedAt()
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    // MARK: - Behavior

    var hapticFeedbackEnabled: Bool {
        didSet {
            defaults.set(hapticFeedbackEnabled, forKey: Keys.hapticFeedbackEnabled)
            touchSettingsUpdatedAt()
        }
    }

    var notificationBadgeEnabled: Bool {
        didSet {
            defaults.set(notificationBadgeEnabled, forKey: Keys.notificationBadgeEnabled)
            touchSettingsUpdatedAt()
        }
    }

    var autoSyncOnLaunch: Bool {
        didSet {
            defaults.set(autoSyncOnLaunch, forKey: Keys.autoSyncOnLaunch)
            touchSettingsUpdatedAt()
        }
    }

    var showAlternativeCalendar: Bool {
        didSet {
            defaults.set(showAlternativeCalendar, forKey: Keys.showBanglaDate)
            touchSettingsUpdatedAt()
        }
    }

    var showBanglaDate: Bool {
        get { showAlternativeCalendar }
        set { showAlternativeCalendar = newValue }
    }

    var alternativeCalendarOption: AlternativeCalendarOption {
        didSet {
            defaults.set(alternativeCalendarOption.rawValue, forKey: Keys.alternativeCalendarOption)
            touchSettingsUpdatedAt()
        }
    }

    var conflictDetectionEnabled: Bool {
        didSet {
            defaults.set(conflictDetectionEnabled, forKey: Keys.conflictDetectionEnabled)
            touchSettingsUpdatedAt()
        }
    }

    var suppressNotificationsDuringFocus: Bool {
        didSet {
            defaults.set(suppressNotificationsDuringFocus, forKey: Keys.suppressNotificationsDuringFocus)
            touchSettingsUpdatedAt()
        }
    }

    var dailyDigestEnabled: Bool {
        didSet {
            defaults.set(dailyDigestEnabled, forKey: Keys.dailyDigestEnabled)
            touchSettingsUpdatedAt()
        }
    }

    var dailyDigestHour: Int {
        didSet {
            let clamped = max(0, min(dailyDigestHour, 23))
            if dailyDigestHour != clamped {
                dailyDigestHour = clamped
                return
            }
            defaults.set(dailyDigestHour, forKey: Keys.dailyDigestHour)
            touchSettingsUpdatedAt()
        }
    }

    var dailyDigestMinute: Int {
        didSet {
            let clamped = max(0, min(dailyDigestMinute, 59))
            if dailyDigestMinute != clamped {
                dailyDigestMinute = clamped
                return
            }
            defaults.set(dailyDigestMinute, forKey: Keys.dailyDigestMinute)
            touchSettingsUpdatedAt()
        }
    }

    var defaultTimeZoneOverride: String? {
        didSet {
            if let v = defaultTimeZoneOverride {
                defaults.set(v, forKey: Keys.defaultTimeZoneOverride)
            } else {
                defaults.removeObject(forKey: Keys.defaultTimeZoneOverride)
            }
            touchSettingsUpdatedAt()
        }
    }

    var settingsUpdatedAt: Date {
        didSet {
            defaults.set(settingsUpdatedAt, forKey: Keys.settingsUpdatedAt)
        }
    }

    private init() {
        if let raw = defaults.string(forKey: Keys.defaultAlertStyle),
           let option = AlertDeliveryOption(rawValue: raw) {
            defaultAlertStyle = option
        } else {
            defaultAlertStyle = .push
        }

        let storedSnooze = defaults.integer(forKey: Keys.defaultSnoozeDuration)
        defaultSnoozeDuration = storedSnooze > 0 ? storedSnooze : 10

        defaultEarlyReminderMinutes = max(0, defaults.integer(forKey: Keys.defaultEarlyReminder))

        if let raw = defaults.string(forKey: Keys.defaultRepeatPattern),
           let pattern = RepeatPattern(rawValue: raw) {
            defaultRepeatPattern = pattern
        } else {
            defaultRepeatPattern = .never
        }

        let priorityRaw = defaults.integer(forKey: Keys.defaultPriority)
        defaultPriority = SchedulePriority(rawValue: priorityRaw) ?? .none

        defaultCalendar = defaults.string(forKey: Keys.defaultCalendar) ?? "Reminders"

        if defaults.object(forKey: Keys.hotNaturalLanguageEnabled) != nil {
            hotNaturalLanguageEnabled = defaults.bool(forKey: Keys.hotNaturalLanguageEnabled)
        } else {
            hotNaturalLanguageEnabled = false
        }

        let firstDay = defaults.integer(forKey: Keys.firstDayOfWeek)
        firstDayOfWeek = (1...7).contains(firstDay) ? firstDay : Calendar.current.firstWeekday

        if let raw = defaults.string(forKey: Keys.timeFormatMode),
           let mode = TimeFormatPreference(rawValue: raw) {
            timeFormatPreference = mode
        } else if defaults.object(forKey: Keys.use24HourTime) != nil {
            let legacyValue = defaults.bool(forKey: Keys.use24HourTime)
            timeFormatPreference = legacyValue ? .twentyFourHour : .twelveHour
        } else {
            timeFormatPreference = .system
        }

        accentColorHex = defaults.string(forKey: Keys.accentColorHex) ?? Self.defaultAccentColorHex
        appearanceMode = defaults.integer(forKey: Keys.appearanceMode)

        if defaults.object(forKey: Keys.hapticFeedbackEnabled) != nil {
            hapticFeedbackEnabled = defaults.bool(forKey: Keys.hapticFeedbackEnabled)
        } else {
            hapticFeedbackEnabled = true
        }

        if defaults.object(forKey: Keys.notificationBadgeEnabled) != nil {
            notificationBadgeEnabled = defaults.bool(forKey: Keys.notificationBadgeEnabled)
        } else {
            notificationBadgeEnabled = true
        }

        if defaults.object(forKey: Keys.autoSyncOnLaunch) != nil {
            autoSyncOnLaunch = defaults.bool(forKey: Keys.autoSyncOnLaunch)
        } else {
            autoSyncOnLaunch = true
        }

        if defaults.object(forKey: Keys.showBanglaDate) != nil {
            showAlternativeCalendar = defaults.bool(forKey: Keys.showBanglaDate)
        } else {
            showAlternativeCalendar = true
        }

        if let raw = defaults.string(forKey: Keys.alternativeCalendarOption),
           let option = AlternativeCalendarOption(rawValue: raw) {
            alternativeCalendarOption = option
        } else {
            alternativeCalendarOption = .bangla
        }

        if defaults.object(forKey: Keys.conflictDetectionEnabled) != nil {
            conflictDetectionEnabled = defaults.bool(forKey: Keys.conflictDetectionEnabled)
        } else {
            conflictDetectionEnabled = true
        }

        if defaults.object(forKey: Keys.suppressNotificationsDuringFocus) != nil {
            suppressNotificationsDuringFocus = defaults.bool(forKey: Keys.suppressNotificationsDuringFocus)
        } else {
            suppressNotificationsDuringFocus = false
        }

        if defaults.object(forKey: Keys.dailyDigestEnabled) != nil {
            dailyDigestEnabled = defaults.bool(forKey: Keys.dailyDigestEnabled)
        } else {
            dailyDigestEnabled = false
        }

        let storedDigestHour = defaults.integer(forKey: Keys.dailyDigestHour)
        dailyDigestHour = (0...23).contains(storedDigestHour) ? storedDigestHour : 20

        let storedDigestMinute = defaults.integer(forKey: Keys.dailyDigestMinute)
        dailyDigestMinute = (0...59).contains(storedDigestMinute) ? storedDigestMinute : 0

        defaultTimeZoneOverride = defaults.string(forKey: Keys.defaultTimeZoneOverride)
        settingsUpdatedAt = defaults.object(forKey: Keys.settingsUpdatedAt) as? Date ?? .distantPast

        removeLegacyDefaults()
    }

    // MARK: - Helpers

    func resetToDefaults() {
        defaultAlertStyle = .push
        defaultSnoozeDuration = 10
        defaultEarlyReminderMinutes = 0
        defaultRepeatPattern = .never
        defaultPriority = .none
        defaultCalendar = "Reminders"
        hotNaturalLanguageEnabled = false
        firstDayOfWeek = Calendar.current.firstWeekday
        timeFormatPreference = .system
        accentColorHex = Self.defaultAccentColorHex
        appearanceMode = 0
        hapticFeedbackEnabled = true
        notificationBadgeEnabled = true
        autoSyncOnLaunch = true
        showAlternativeCalendar = true
        alternativeCalendarOption = .bangla
        defaultTimeZoneOverride = nil
        conflictDetectionEnabled = true
        suppressNotificationsDuringFocus = false
        dailyDigestEnabled = false
        dailyDigestHour = 20
        dailyDigestMinute = 0
        touchSettingsUpdatedAt()
    }

    func beginSettingsBatchUpdate() {
        suppressSettingsUpdatedAtWrites = true
    }

    func endSettingsBatchUpdate(persisting date: Date? = nil) {
        suppressSettingsUpdatedAtWrites = false
        if let date {
            settingsUpdatedAt = date
        } else {
            touchSettingsUpdatedAt()
        }
    }

    private func touchSettingsUpdatedAt() {
        guard !suppressSettingsUpdatedAtWrites else { return }
        settingsUpdatedAt = Date()
    }

    private func removeLegacyDefaults() {
        defaults.removeObject(forKey: LegacyKeys.timelineStartHour)
        defaults.removeObject(forKey: LegacyKeys.timelineEndHour)
        defaults.removeObject(forKey: LegacyKeys.preferredAppIconName)
    }
}

// MARK: - Color Hex Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        guard hexSanitized.count == 6,
              let intValue = UInt64(hexSanitized, radix: 16)
        else { return nil }
        let r = Double((intValue >> 16) & 0xFF) / 255.0
        let g = Double((intValue >> 8) & 0xFF) / 255.0
        let b = Double(intValue & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    var hexString: String {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var r: CGFloat = 0; var g: CGFloat = 0; var b: CGFloat = 0; var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        #else
        return "#4F9FF8"
        #endif
    }
}
