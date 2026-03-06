import Foundation
import SwiftData

enum AlarmSoundOption: String, Codable, CaseIterable, Identifiable {
    case defaultRingtone
    case studioRadar
    case studioOpening
    case studioBeacon
    case studioChimes
    case studioConstellation
    case studioRipples
    case alarm
    case apex
    case ascending
    case bark
    case beacon
    case bellTower
    case blues
    case boing
    case bulletin
    case byTheSeaside
    case chimes
    case circuit
    case constellation
    case cosmic
    case crickets
    case crystals
    case digital
    case doorbell
    case duck
    case harp
    case hillside
    case illuminate
    case marimba
    case motorcycle
    case nightOwl
    case oldCarHorn
    case oldPhone
    case opening
    case pianoRiff
    case pinball
    case playtime
    case presto
    case radar
    case radiate
    case ripples
    case robot
    case radial
    case arpeggio
    case breaking
    case canopy
    case chalet
    case chirp
    case daybreak
    case departure
    case dollop
    case journey
    case kettle
    case mercury
    case milkyWay
    case quad
    case reflection
    case scavenger
    case seedling
    case shelter
    case sprinkles
    case steps
    case storytime
    case tease
    case tilt
    case unfold
    case valley
    case critical

    // Legacy values kept for backward compatibility with previously saved schedules.
    case anticipate
    case bloom
    case calypso
    case chooChoo
    case descent
    case fanfare
    case ladder
    case minuet
    case newsFlash
    case noir
    case sherwoodForest
    case spell
    case suspense
    case telegraph
    case tiptoes
    case typewriters
    case update
    case defaultSound
    case newMail
    case mailSent
    case voicemail
    case receivedMessage
    case sentMessage
    case smsTone1
    case smsTone2
    case smsTone3
    case smsTone4

    var id: String { rawValue }

    static let selectableCases: [AlarmSoundOption] = [
        .defaultRingtone,
        .studioRadar,
        .studioOpening,
        .studioBeacon,
        .studioChimes,
        .studioConstellation,
        .studioRipples
    ]

    var displayName: String {
        switch self {
        case .defaultRingtone:
            return "Default Ringtone"
        case .studioRadar:
            return "Radar (Studio)"
        case .studioOpening:
            return "Opening (Studio)"
        case .studioBeacon:
            return "Beacon (Studio)"
        case .studioChimes:
            return "Chimes (Studio)"
        case .studioConstellation:
            return "Constellation (Studio)"
        case .studioRipples:
            return "Ripples (Studio)"
        case .alarm:
            return "Alarm"
        case .apex:
            return "Apex"
        case .ascending:
            return "Ascending"
        case .bark:
            return "Bark"
        case .beacon:
            return "Beacon"
        case .bellTower:
            return "Bell Tower"
        case .blues:
            return "Blues"
        case .boing:
            return "Boing"
        case .bulletin:
            return "Bulletin"
        case .byTheSeaside:
            return "By The Seaside"
        case .chimes:
            return "Chimes"
        case .circuit:
            return "Circuit"
        case .constellation:
            return "Constellation"
        case .cosmic:
            return "Cosmic"
        case .crickets:
            return "Crickets"
        case .crystals:
            return "Crystals"
        case .digital:
            return "Digital"
        case .doorbell:
            return "Doorbell"
        case .duck:
            return "Duck"
        case .harp:
            return "Harp"
        case .hillside:
            return "Hillside"
        case .illuminate:
            return "Illuminate"
        case .marimba:
            return "Marimba"
        case .motorcycle:
            return "Motorcycle"
        case .nightOwl:
            return "Night Owl"
        case .oldCarHorn:
            return "Old Car Horn"
        case .oldPhone:
            return "Old Phone"
        case .opening:
            return "Opening"
        case .pianoRiff:
            return "Piano Riff"
        case .pinball:
            return "Pinball"
        case .playtime:
            return "Playtime"
        case .presto:
            return "Presto"
        case .radar:
            return "Radar"
        case .radiate:
            return "Radiate"
        case .ripples:
            return "Ripples"
        case .robot:
            return "Robot"
        case .radial:
            return "Radial"
        case .arpeggio:
            return "Arpeggio"
        case .breaking:
            return "Breaking"
        case .canopy:
            return "Canopy"
        case .chalet:
            return "Chalet"
        case .chirp:
            return "Chirp"
        case .daybreak:
            return "Daybreak"
        case .departure:
            return "Departure"
        case .dollop:
            return "Dollop"
        case .journey:
            return "Journey"
        case .kettle:
            return "Kettle"
        case .mercury:
            return "Mercury"
        case .milkyWay:
            return "Milky Way"
        case .quad:
            return "Quad"
        case .reflection:
            return "Reflection"
        case .scavenger:
            return "Scavenger"
        case .seedling:
            return "Seedling"
        case .shelter:
            return "Shelter"
        case .sprinkles:
            return "Sprinkles"
        case .steps:
            return "Steps"
        case .storytime:
            return "Storytime"
        case .tease:
            return "Tease"
        case .tilt:
            return "Tilt"
        case .unfold:
            return "Unfold"
        case .valley:
            return "Valley"
        case .critical:
            return "Critical"
        case .anticipate:
            return "Anticipate"
        case .bloom:
            return "Bloom"
        case .calypso:
            return "Calypso"
        case .chooChoo:
            return "Choo Choo"
        case .descent:
            return "Descent"
        case .fanfare:
            return "Fanfare"
        case .ladder:
            return "Ladder"
        case .minuet:
            return "Minuet"
        case .newsFlash:
            return "News Flash"
        case .noir:
            return "Noir"
        case .sherwoodForest:
            return "Sherwood Forest"
        case .spell:
            return "Spell"
        case .suspense:
            return "Suspense"
        case .telegraph:
            return "Telegraph"
        case .tiptoes:
            return "Tiptoes"
        case .typewriters:
            return "Typewriters"
        case .update:
            return "Update"
        case .defaultSound:
            return "Default Ringtone"
        case .newMail:
            return "New Mail"
        case .mailSent:
            return "Mail Sent"
        case .voicemail:
            return "Voicemail"
        case .receivedMessage:
            return "Received Message"
        case .sentMessage:
            return "Sent Message"
        case .smsTone1:
            return "SMS Tone 1"
        case .smsTone2:
            return "SMS Tone 2"
        case .smsTone3:
            return "SMS Tone 3"
        case .smsTone4:
            return "SMS Tone 4"
        }
    }

    /// The actual Apple ringtone / alert-tone filename (without extension).
    /// Ringtones live in `/Library/Ringtones/`, alert tones in `/System/Library/Audio/UISounds/`.
    var ringtoneFileName: String {
        switch self {
        // Ringtones  (/Library/Ringtones/<name>.m4r)
        case .defaultRingtone:    return "Default"
        case .studioRadar:        return "tone_radar"
        case .studioOpening:      return "tone_opening"
        case .studioBeacon:       return "tone_beacon"
        case .studioChimes:       return "tone_chimes"
        case .studioConstellation:return "tone_constellation"
        case .studioRipples:      return "tone_ripples"
        case .alarm:              return "Alarm"
        case .apex:               return "Apex"
        case .ascending:          return "Ascending"
        case .bark:               return "Bark"
        case .beacon:             return "Beacon"
        case .bellTower:          return "Bell Tower"
        case .blues:              return "Blues"
        case .boing:              return "Boing"
        case .bulletin:           return "Bulletin"
        case .byTheSeaside:       return "By The Seaside"
        case .chimes:             return "Chimes"
        case .circuit:            return "Circuit"
        case .constellation:      return "Constellation"
        case .cosmic:             return "Cosmic"
        case .crickets:           return "Crickets"
        case .crystals:           return "Crystals"
        case .digital:            return "Digital"
        case .doorbell:           return "Doorbell"
        case .duck:               return "Duck"
        case .harp:               return "Harp"
        case .hillside:           return "Hillside"
        case .illuminate:         return "Illuminate"
        case .marimba:            return "Marimba"
        case .motorcycle:         return "Motorcycle"
        case .nightOwl:           return "Night Owl"
        case .oldCarHorn:         return "Old Car Horn"
        case .oldPhone:           return "Old Phone"
        case .opening:            return "Opening"
        case .pianoRiff:          return "Piano Riff"
        case .pinball:            return "Pinball"
        case .playtime:           return "Playtime"
        case .presto:             return "Presto"
        case .radar:              return "Radar"
        case .radiate:            return "Radiate"
        case .ripples:            return "Ripples"
        case .robot:              return "Robot"
        case .radial:             return "Radial"
        // Modern ringtones (iOS 17+)
        case .arpeggio:           return "Arpeggio"
        case .breaking:           return "Breaking"
        case .canopy:             return "Canopy"
        case .chalet:             return "Chalet"
        case .chirp:              return "Chirp"
        case .daybreak:           return "Daybreak"
        case .departure:          return "Departure"
        case .dollop:             return "Dollop"
        case .journey:            return "Journey"
        case .kettle:             return "Kettle"
        case .mercury:            return "Mercury"
        case .milkyWay:           return "Milky Way"
        case .quad:               return "Quad"
        case .reflection:         return "Reflection"
        case .scavenger:          return "Scavenger"
        case .seedling:           return "Seedling"
        case .shelter:            return "Shelter"
        case .sprinkles:          return "Sprinkles"
        case .steps:              return "Steps"
        case .storytime:          return "Storytime"
        case .tease:              return "Tease"
        case .tilt:               return "Tilt"
        case .unfold:             return "Unfold"
        case .valley:             return "Valley"
        case .critical:           return "Alarm"
        // Legacy alert tones  (/System/Library/Audio/UISounds/<name>.caf)
        case .anticipate:         return "Anticipate"
        case .bloom:              return "Bloom"
        case .calypso:            return "Calypso"
        case .chooChoo:           return "Choo_Choo"
        case .descent:            return "Descent"
        case .fanfare:            return "Fanfare"
        case .ladder:             return "Ladder"
        case .minuet:             return "Minuet"
        case .newsFlash:          return "News_Flash"
        case .noir:               return "Noir"
        case .sherwoodForest:     return "Sherwood_Forest"
        case .spell:              return "Spell"
        case .suspense:           return "Suspense"
        case .telegraph:          return "Telegraph"
        case .tiptoes:            return "Tiptoes"
        case .typewriters:        return "Typewriters"
        case .update:             return "Update"
        case .defaultSound:       return "Default"
        case .newMail:            return "new-mail"
        case .mailSent:           return "mail-sent"
        case .voicemail:          return "Voicemail"
        case .receivedMessage:    return "ReceivedMessage"
        case .sentMessage:        return "SentMessage"
        case .smsTone1:           return "sms-received1"
        case .smsTone2:           return "sms-received2"
        case .smsTone3:           return "sms-received3"
        case .smsTone4:           return "sms-received4"
        }
    }

    /// Distinct SystemSoundID for haptic/audio preview.
    /// Alert tones (1014-1030) have well-known IDs; ringtone files are played via AVAudioPlayer.
    var previewSystemSoundID: UInt32? {
        switch self {
        case .anticipate:      return 1014
        case .bloom:           return 1015
        case .calypso:         return 1016
        case .chooChoo:        return 1017
        case .descent:         return 1018
        case .fanfare:         return 1019
        case .ladder:          return 1020
        case .minuet:          return 1021
        case .newsFlash:       return 1022
        case .noir:            return 1023
        case .sherwoodForest:  return 1024
        case .spell:           return 1025
        case .suspense:        return 1026
        case .telegraph:       return 1027
        case .tiptoes:         return 1028
        case .typewriters:     return 1029
        case .update:          return 1030
        case .newMail:         return 1000
        case .mailSent:        return 1001
        case .voicemail:       return 1002
        case .receivedMessage: return 1003
        case .sentMessage:     return 1004
        case .smsTone1:        return 1007
        case .smsTone2:        return 1008
        case .smsTone3:        return 1009
        case .smsTone4:        return 1010
        default:
            return nil   // Ringtone: use AVAudioPlayer with file path
        }
    }

    /// URL for the ringtone/alert file on the device file system, if it exists.
    var ringtoneFileURL: URL? {
        let fileManager = FileManager.default
        for url in ringtonePathCandidates {
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// Notification API expects a ringtone name token, not the display label.
    var notificationRingtoneName: String {
        // Use a deterministic token directly to avoid heavy file indexing work on app launch.
        return ringtoneFileName
    }

    /// Bundled custom alarm sound file name (without extension), if available.
    nonisolated var bundledSoundFileName: String? {
        switch self {
        case .defaultRingtone:
            return "alarm_sound"
        case .studioRadar:
            return "tone_radar"
        case .studioOpening:
            return "tone_opening"
        case .studioBeacon:
            return "tone_beacon"
        case .studioChimes:
            return "tone_chimes"
        case .studioConstellation:
            return "tone_constellation"
        case .studioRipples:
            return "tone_ripples"
        default:
            return nil
        }
    }

    /// Bundled .caf fallback for sounds that have a studio equivalent in the app bundle.
    /// E.g. `.radar` has no bundled file, but `.studioRadar` ships `tone_radar.caf`.
    nonisolated var fallbackBundledSoundFileName: String? {
        switch self {
        case .radar:          return "tone_radar"
        case .opening:        return "tone_opening"
        case .beacon:         return "tone_beacon"
        case .chimes:         return "tone_chimes"
        case .constellation:  return "tone_constellation"
        case .ripples:        return "tone_ripples"
        default:              return nil
        }
    }

    /// Best available bundled sound file name (own or studio fallback).
    nonisolated var bestAvailableBundledSoundFileName: String? {
        bundledSoundFileName ?? fallbackBundledSoundFileName
    }

    var usesCriticalAlert: Bool {
        self == .critical
    }

    private var ringtoneLookupCandidates: [String] {
        let seed = [
            ringtoneFileName,
            ringtoneFileName.replacingOccurrences(of: " ", with: "_"),
            ringtoneFileName.replacingOccurrences(of: "_", with: " "),
            displayName,
            displayName.replacingOccurrences(of: " ", with: "_"),
            rawValue,
            rawValue.replacingOccurrences(of: "_", with: " "),
            rawValue.replacingOccurrences(of: " ", with: "_")
        ]

        var seen = Set<String>()
        var unique: [String] = []

        for value in seed {
            let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(value)
        }

        return unique
    }

    private var ringtonePathCandidates: [URL] {
        let cacheKey = rawValue
        if let cached = AlarmSoundOption.ringtonePathCandidatesCache[cacheKey] {
            return cached
        }

        let directories = ["/Library/Ringtones", "/System/Library/Audio/UISounds"]
        let extensions = ["m4r", "caf", "aiff", "wav", "m4a", "mp3", "aac"]
        var urls: [URL] = []
        urls.reserveCapacity(directories.count * ringtoneLookupCandidates.count * extensions.count)

        for directory in directories {
            let baseURL = URL(fileURLWithPath: directory, isDirectory: true)
            for fileName in ringtoneLookupCandidates {
                for ext in extensions {
                    urls.append(
                        baseURL
                            .appendingPathComponent(fileName)
                            .appendingPathExtension(ext)
                    )
                }
            }
        }

        AlarmSoundOption.ringtonePathCandidatesCache[cacheKey] = urls
        return urls
    }

    private static var ringtonePathCandidatesCache: [String: [URL]] = [:]
}

@Model
final class Schedule {
    @Attribute(.unique)
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var isSoftDeleted: Bool
    var lastModifiedDeviceID: String
    var syncVersion: Int
    var lastSyncedVersion: Int
    var conflictResolutionTag: String?
    var title: String
    var notes: String?
    var urlString: String?
    var scheduledDate: Date
    var isUrgent: Bool
    var repeatPatternRaw: String
    var repeatWeekdays: [Int] = Array(1...7)
    var repeatInterval: Int = 1
    var repeatEndCount: Int = 0
    var excludedOccurrenceDates: [Date] = []
    var repeatEndOptionRaw: String = RepeatEndOption.never.rawValue
    var repeatEndDate: Date?
    var alertDeliveryRaw: String = AlertDeliveryOption.push.rawValue
    var alarmSoundRaw: String = AlarmSoundOption.defaultRingtone.rawValue
    var alarmSnoozeEnabled: Bool = true
    var alarmSnoozeMinutes: Int = 10
    var earlyReminderMinutes: Int?
    var additionalReminderMinutes: [Int] = []
    var timeZoneIdentifier: String?
    var listName: String
    var tags: [String]
    var isFlagged: Bool
    var isCompleted: Bool = false
    var priorityRaw: Int

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        isSoftDeleted: Bool = false,
        lastModifiedDeviceID: String = "",
        syncVersion: Int = 0,
        lastSyncedVersion: Int = 0,
        conflictResolutionTag: String? = nil,
        title: String,
        notes: String? = nil,
        urlString: String? = nil,
        scheduledDate: Date = Date(),
        isUrgent: Bool = false,
        repeatPattern: RepeatPattern = .never,
        repeatWeekdays: [Int] = Array(1...7),
        repeatInterval: Int = 1,
        repeatEndCount: Int = 0,
        excludedOccurrenceDates: [Date] = [],
        repeatEndOption: RepeatEndOption = .never,
        repeatEndDate: Date? = nil,
        alertDeliveryOption: AlertDeliveryOption = .push,
        alarmSoundOption: AlarmSoundOption = .defaultRingtone,
        alarmSnoozeEnabled: Bool = true,
        alarmSnoozeMinutes: Int = 10,
        earlyReminderMinutes: Int? = nil,
        additionalReminderMinutes: [Int] = [],
        timeZoneIdentifier: String? = nil,
        listName: String = "Reminders",
        tags: [String] = [],
        isFlagged: Bool = false,
        isCompleted: Bool = false,
        priority: SchedulePriority = .none
    ) {
        let normalizedUpdatedAt = max(createdAt, updatedAt)
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = normalizedUpdatedAt
        self.deletedAt = deletedAt
        self.isSoftDeleted = isSoftDeleted
        self.lastModifiedDeviceID = lastModifiedDeviceID
        self.syncVersion = max(0, syncVersion)
        self.lastSyncedVersion = max(0, lastSyncedVersion)
        self.conflictResolutionTag = conflictResolutionTag
        self.title = title
        self.notes = notes
        self.urlString = urlString
        self.scheduledDate = scheduledDate
        self.isUrgent = isUrgent
        self.repeatPatternRaw = repeatPattern.rawValue
        self.repeatWeekdays = repeatWeekdays
        self.repeatInterval = max(1, repeatInterval)
        self.repeatEndCount = max(0, repeatEndCount)
        self.excludedOccurrenceDates = Array(Set(excludedOccurrenceDates.map(\.startOfDay))).sorted()
        self.repeatEndOptionRaw = repeatEndOption.rawValue
        self.repeatEndDate = repeatEndDate
        self.alertDeliveryRaw = alertDeliveryOption.rawValue
        self.alarmSoundRaw = alarmSoundOption.rawValue
        self.alarmSnoozeEnabled = alarmSnoozeEnabled
        self.alarmSnoozeMinutes = max(1, min(alarmSnoozeMinutes, 1439))
        self.earlyReminderMinutes = earlyReminderMinutes
        self.additionalReminderMinutes = additionalReminderMinutes
        self.timeZoneIdentifier = timeZoneIdentifier
        self.listName = listName
        self.tags = tags
        self.isFlagged = isFlagged
        self.isCompleted = isCompleted
        self.priorityRaw = priority.rawValue
    }

    var repeatPattern: RepeatPattern {
        get { RepeatPattern(rawValue: repeatPatternRaw) ?? .never }
        set { repeatPatternRaw = newValue.rawValue }
    }

    var repeatEndOption: RepeatEndOption {
        get { RepeatEndOption(rawValue: repeatEndOptionRaw) ?? .never }
        set { repeatEndOptionRaw = newValue.rawValue }
    }

    var alertDeliveryOption: AlertDeliveryOption {
        get {
            if let option = AlertDeliveryOption(rawValue: alertDeliveryRaw) {
                return option
            }

            switch alertDeliveryRaw {
            case "Push Notification":
                return .push
            case "Alarm Notification", "Alarm":
                return .alarm
            default:
                return isUrgent ? .alarm : .push
            }
        }
        set { alertDeliveryRaw = newValue.rawValue }
    }

    var alarmSoundOption: AlarmSoundOption {
        get {
            AlarmSoundOption(rawValue: alarmSoundRaw) ?? .defaultRingtone
        }
        set { alarmSoundRaw = newValue.rawValue }
    }

    var priority: SchedulePriority {
        get { SchedulePriority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }

    var scheduleTimeZone: TimeZone? {
        get {
            if let id = timeZoneIdentifier,
               let resolved = TimeZone(identifier: id) {
                return resolved
            }

            if let overrideID = AppSettings.shared.defaultTimeZoneOverride,
               let overrideZone = TimeZone(identifier: overrideID) {
                return overrideZone
            }

            return nil
        }
        set { timeZoneIdentifier = newValue?.identifier }
    }

    /// All reminder offsets (primary + additional), sorted ascending.
    var allReminderMinutes: [Int] {
        var all: [Int] = []
        if let primary = earlyReminderMinutes, primary > 0 { all.append(primary) }
        all.append(contentsOf: additionalReminderMinutes.filter { $0 > 0 })
        return Array(Set(all)).sorted()
    }

    var url: URL? {
        guard let urlString else { return nil }
        return URL(string: urlString)
    }

    var timeString: String {
        ScheduleFormatters.timeString(from: scheduledDate, timeZone: scheduleTimeZone)
    }

    var dateString: String {
        ScheduleFormatters.date.string(from: scheduledDate)
    }

    var hourOffset: CGFloat {
        var calendar = Calendar.current
        if let tz = scheduleTimeZone {
            calendar.timeZone = tz
        }
        let hour = calendar.component(.hour, from: scheduledDate)
        let minute = calendar.component(.minute, from: scheduledDate)
        return CGFloat(hour) + CGFloat(minute) / 60.0
    }
}

private enum ScheduleFormatters {
    static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        return formatter
    }()

    static func timeString(from date: Date, timeZone: TimeZone?) -> String {
        let preference = AppSettings.shared.timeFormatPreference
        let timeZoneKey = timeZone?.identifier ?? "system"
        let cacheKey = "\(preference.rawValue)|\(timeZoneKey)"

        if let formatter = cachedTimeFormatters[cacheKey] {
            return formatter.string(from: date)
        }

        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = timeZone

        switch preference {
        case .system:
            formatter.timeStyle = .short
        case .twelveHour:
            formatter.dateFormat = "h:mm a"
        case .twentyFourHour:
            formatter.dateFormat = "HH:mm"
        }

        cachedTimeFormatters[cacheKey] = formatter
        return formatter.string(from: date)
    }

    private static var cachedTimeFormatters: [String: DateFormatter] = [:]
}
