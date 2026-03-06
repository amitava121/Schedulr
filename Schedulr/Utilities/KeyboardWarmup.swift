#if os(iOS)
import UIKit

enum KeyboardWarmup {
    private static var didPrewarm = false
    private static var isPrewarming = false
    private static var retryCount = 0
    private static let maxRetryCount = 6

    static func prewarmIfNeeded() {
        guard !didPrewarm, !isPrewarming else { return }
        isPrewarming = true
        retryCount = 0
        attemptPrewarm(after: 0.35)
    }

    private static func attemptPrewarm(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard !didPrewarm else {
                isPrewarming = false
                return
            }

            guard
                let windowScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive }),
                let window = windowScene.windows.first(where: \.isKeyWindow),
                UIResponder.currentFirstResponder == nil
            else {
                retryCount += 1
                if retryCount <= maxRetryCount {
                    attemptPrewarm(after: 0.22)
                } else {
                    isPrewarming = false
                }
                return
            }

            let warmupField = UITextField(frame: .zero)
            warmupField.isHidden = true
            warmupField.autocorrectionType = .no
            warmupField.spellCheckingType = .no

            window.addSubview(warmupField)
            _ = warmupField.becomeFirstResponder()
            _ = warmupField.resignFirstResponder()
            warmupField.removeFromSuperview()

            didPrewarm = true
            isPrewarming = false
        }
    }
}

private extension UIResponder {
    static var currentFirstResponder: UIResponder? {
        _currentFirstResponder = nil
        UIApplication.shared.sendAction(
            #selector(captureFirstResponder(_:)),
            to: nil,
            from: nil,
            for: nil
        )
        return _currentFirstResponder
    }

    @objc func captureFirstResponder(_ sender: Any) {
        UIResponder._currentFirstResponder = self
    }

    private static weak var _currentFirstResponder: UIResponder?
}
#endif
