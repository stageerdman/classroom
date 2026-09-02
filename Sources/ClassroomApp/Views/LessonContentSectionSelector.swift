import ClassroomCore
import SwiftUI

/// Top category selector for the lesson pane: Page, Notes, (future
/// sections). Tapping toggles a section in/out of the current selection —
/// see `ContentSectionSelectionService` for the underlying rules (single
/// view, or a 2-pane split when two sections are selected).
struct LessonContentSectionSelector: View {
    let selectedSections: [LessonContentSection]
    let onToggle: (LessonContentSection) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(LessonContentSection.allCases) { section in
                let isSelected = selectedSections.contains(section)

                Button(section.title) {
                    onToggle(section)
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.15)) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 6)
                )
            }
        }
    }
}
