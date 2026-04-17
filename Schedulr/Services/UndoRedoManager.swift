import Foundation
import SchedulrLogic

/// Manages undo/redo for schedule operations using a custom action stack.
/// Integrates with SwiftUI's environment UndoManager when available.
@Observable
final class UndoRedoManager {
    static let shared = UndoRedoManager()

    private(set) var undoStack: [ScheduleAction] = []
    private(set) var redoStack: [ScheduleAction] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var undoActionName: String? { undoStack.last?.description }
    var redoActionName: String? { redoStack.last?.description }

    private let maxStackSize = 50

    private init() {}

    // MARK: - Record

    func record(_ action: ScheduleAction) {
        undoStack.append(action)
        redoStack.removeAll()

        // Trim stack
        if undoStack.count > maxStackSize {
            undoStack.removeFirst(undoStack.count - maxStackSize)
        }
    }

    // MARK: - Undo / Redo

    func undo(using handler: ScheduleActionHandler) {
        guard let action = undoStack.popLast() else { return }
        let inverse = action.inverse
        handler.execute(inverse)
        redoStack.append(action)
    }

    func redo(using handler: ScheduleActionHandler) {
        guard let action = redoStack.popLast() else { return }
        handler.execute(action)
        undoStack.append(action)
    }

    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}

// MARK: - Schedule Action

enum ScheduleAction {
    case create(ScheduleSnapshot)
    case delete(ScheduleSnapshot)
    case update(old: ScheduleSnapshot, new: ScheduleSnapshot)
    case complete(id: UUID, wasCompleted: Bool)
    case reschedule(id: UUID, oldDate: Date, newDate: Date)

    var description: String {
        switch self {
        case .create(let s): return "Create \"\(s.title)\""
        case .delete(let s): return "Delete \"\(s.title)\""
        case .update(_, let new): return "Edit \"\(new.title)\""
        case .complete(_, let was): return was ? "Mark Incomplete" : "Mark Complete"
        case .reschedule(_, _, _): return "Reschedule"
        }
    }

    var inverse: ScheduleAction {
        switch self {
        case .create(let s): return .delete(s)
        case .delete(let s): return .create(s)
        case .update(let old, let new): return .update(old: new, new: old)
        case .complete(let id, let was): return .complete(id: id, wasCompleted: !was)
        case .reschedule(let id, let old, let new): return .reschedule(id: id, oldDate: new, newDate: old)
        }
    }
}

// MARK: - Action Handler Protocol

/// Protocol that the ScheduleViewModel conforms to for executing undo/redo actions.
protocol ScheduleActionHandler {
    func execute(_ action: ScheduleAction)
}
