import Foundation

/// Pure selection logic for the lesson pane's top category selector.
///
/// Selection is an ordered list (order = when each section was added, not
/// display order) capped at 2 — that's what turns into a split view.
/// Tapping a section: adds it if unselected (making room by dropping the
/// oldest selection once already at the cap), removes it if selected
/// unless it's the only one selected (never leaves zero sections shown).
public enum ContentSectionSelectionService {
    public static let maxSelected = 2

    public static func toggling(_ section: LessonContentSection, in selection: [LessonContentSection]) -> [LessonContentSection] {
        if let index = selection.firstIndex(of: section) {
            guard selection.count > 1 else {
                return selection
            }
            var updated = selection
            updated.remove(at: index)
            return updated
        }

        var updated = selection
        if updated.count >= maxSelected {
            updated.removeFirst()
        }
        updated.append(section)
        return updated
    }
}
