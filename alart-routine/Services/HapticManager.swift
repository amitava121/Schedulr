import Foundation

#if canImport(UIKit)
import UIKit

enum HapticManager {
    private static func onMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        onMain {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred()
        }
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        onMain {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(type)
        }
    }

    static func selection() {
        onMain {
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            generator.selectionChanged()
        }
    }
}
#else
enum HapticManager {
    enum FeedbackStyle { case light, medium, heavy }
    enum FeedbackType { case success, warning, error }

    static func impact(_ style: FeedbackStyle = .medium) {}
    static func notification(_ type: FeedbackType) {}
    static func selection() {}
}
#endif
