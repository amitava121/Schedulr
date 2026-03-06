import Foundation
import ActivityKit

// MARK: - Live Activity Attributes

struct AlarmActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var scheduleTitle: String
        var scheduledTime: Date
        var isSnoozing: Bool
        var snoozeUntil: Date?
        var elapsedSeconds: Int
    }

    var scheduleID: String
    var alarmSoundName: String
}

// MARK: - Live Activity Manager

@available(iOS 16.1, *)
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private var currentActivity: Activity<AlarmActivityAttributes>?

    private init() {}

    func startAlarmActivity(
        scheduleID: UUID,
        title: String,
        scheduledTime: Date,
        alarmSoundName: String
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = AlarmActivityAttributes(
            scheduleID: scheduleID.uuidString,
            alarmSoundName: alarmSoundName
        )

        let state = AlarmActivityAttributes.ContentState(
            scheduleTitle: title,
            scheduledTime: scheduledTime,
            isSnoozing: false,
            snoozeUntil: nil,
            elapsedSeconds: 0
        )

        do {
            let content = ActivityContent(state: state, staleDate: nil)
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            currentActivity = activity
        } catch {
            print("Failed to start live activity: \(error)")
        }
    }

    func updateSnooze(until snoozeDate: Date) {
        guard let activity = currentActivity else { return }

        let updatedState = AlarmActivityAttributes.ContentState(
            scheduleTitle: activity.content.state.scheduleTitle,
            scheduledTime: activity.content.state.scheduledTime,
            isSnoozing: true,
            snoozeUntil: snoozeDate,
            elapsedSeconds: activity.content.state.elapsedSeconds
        )

        Task {
            let content = ActivityContent(state: updatedState, staleDate: snoozeDate)
            await activity.update(content)
        }
    }

    func stopAlarmActivity() {
        guard let activity = currentActivity else { return }

        let finalState = AlarmActivityAttributes.ContentState(
            scheduleTitle: activity.content.state.scheduleTitle,
            scheduledTime: activity.content.state.scheduledTime,
            isSnoozing: false,
            snoozeUntil: nil,
            elapsedSeconds: activity.content.state.elapsedSeconds
        )

        Task {
            let content = ActivityContent(state: finalState, staleDate: nil)
            await activity.end(content, dismissalPolicy: .immediate)
            await MainActor.run {
                currentActivity = nil
            }
        }
    }

    var isActivityActive: Bool {
        currentActivity != nil
    }
}
