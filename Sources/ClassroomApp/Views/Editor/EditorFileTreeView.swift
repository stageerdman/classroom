import ClassroomCore
import SwiftUI

/// Raw filesystem tree for the module being edited — every visible file
/// and folder, including ones normal browsing never shows (`Attachments/`,
/// `Removed/`). Doubles as a drag source for Finder-style drag-and-drop
/// into the structured outline or a lesson's drop zones.
struct EditorFileTreeView: View {
    @ObservedObject var viewModel: ClassroomEditorViewModel

    var body: some View {
        List(viewModel.fileTree, children: \.outlineChildren) { node in
            row(for: node)
        }
        .listStyle(.sidebar)
    }

    private func row(for node: FileNode) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon(for: node))
                .foregroundStyle(node.isLessonFolder ? Color.accentColor : .secondary)
                .frame(width: 16)
            Text(node.name)
                .lineLimit(1)
        }
        .draggable(node.url)
        .contextMenu {
            if isTransformEligible(node) {
                Button("Transform to Lesson") {
                    viewModel.beginTransform(node)
                }
            }
        }
    }

    private func icon(for node: FileNode) -> String {
        if node.isLessonFolder {
            return "play.rectangle"
        }
        if node.isDirectory {
            return "folder"
        }
        return "doc"
    }

    private func isTransformEligible(_ node: FileNode) -> Bool {
        node.structuralKind == .category && !node.children.contains { $0.isDirectory }
    }
}

extension FileNode {
    /// `List(_:children:)` needs an *optional* children keypath — nil means
    /// "leaf, no disclosure arrow," which files should get but empty
    /// folders shouldn't.
    var outlineChildren: [FileNode]? {
        isDirectory ? children : nil
    }
}
