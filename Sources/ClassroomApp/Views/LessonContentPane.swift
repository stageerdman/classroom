import ClassroomCore
import SwiftUI

/// Renders whatever's currently selected in `LessonContentSectionSelector`:
/// one section full-width, or two side by side (capped at 2 by
/// `ContentSectionSelectionService` — this view just trusts that).
struct LessonContentPane<Content: View>: View {
    let sections: [LessonContentSection]
    @ViewBuilder let content: (LessonContentSection) -> Content

    var body: some View {
        if orderedSections.count > 1 {
            HStack(alignment: .top, spacing: 20) {
                ForEach(Array(orderedSections.enumerated()), id: \.element) { index, section in
                    content(section)
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    if index < orderedSections.count - 1 {
                        Divider()
                    }
                }
            }
        } else if let section = orderedSections.first {
            content(section)
        }
    }

    /// Fixed left-to-right display order (`allCases`), independent of the
    /// order sections were selected in.
    private var orderedSections: [LessonContentSection] {
        LessonContentSection.allCases.filter { sections.contains($0) }
    }
}
