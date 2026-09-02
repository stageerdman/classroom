import Foundation

/// A category shown in the lesson pane's top selector. Ordered by
/// `allCases` — that's the fixed left-to-right display order, independent
/// of selection order.
public enum LessonContentSection: String, CaseIterable, Equatable, Identifiable {
    case page
    case notes

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .page: return "Page"
        case .notes: return "Notes"
        }
    }
}
