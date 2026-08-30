import Foundation

/// Rewrites `ClassroomMetadata` after an in-app rename or move so playback
/// position, completion state, and custom ordering survive the operation
/// instead of being silently orphaned under the old path.
///
/// A rename or move changes the relative path that identifies a Module,
/// Category, or Lesson. `lessonState` is always keyed by full lesson path,
/// so it cascades by prefix regardless of which kind of node changed.
/// `lessonOrder`/`categoryOrder` are dictionaries keyed by *parent* path
/// with arrays of bare child names as values — a Module or Category rename
/// relocates the dictionary key; a Category or Lesson rename-in-place
/// rewrites the bare name inside its parent's array; a Lesson move to a
/// different parent just drops the stale array entry and lets the existing
/// scan-merge logic re-append it naturally in its new location.
public enum MetadataMigrationService {
    public static func migrate(
        _ metadata: ClassroomMetadata,
        kind: ClassroomNodeKind,
        oldPath: String,
        newPath: String
    ) -> ClassroomMetadata {
        var updated = metadata

        updated.lessonState = Dictionary(
            uniqueKeysWithValues: updated.lessonState.map { key, value in
                (rewritePrefix(key, oldPath: oldPath, newPath: newPath), value)
            }
        )
        updated.lessonOrder = Dictionary(
            uniqueKeysWithValues: updated.lessonOrder.map { key, value in
                (rewritePrefix(key, oldPath: oldPath, newPath: newPath), value)
            }
        )
        updated.categoryOrder = Dictionary(
            uniqueKeysWithValues: updated.categoryOrder.map { key, value in
                (rewritePrefix(key, oldPath: oldPath, newPath: newPath), value)
            }
        )

        switch kind {
        case .module:
            updated.moduleOrder = updated.moduleOrder.map {
                $0 == leafName(oldPath) ? leafName(newPath) : $0
            }

        case .category:
            let parent = parentPath(of: oldPath)
            if parentPath(of: newPath) == parent {
                updated.categoryOrder[parent] = updated.categoryOrder[parent]?.map {
                    $0 == leafName(oldPath) ? leafName(newPath) : $0
                }
            } else {
                updated.categoryOrder[parent]?.removeAll { $0 == leafName(oldPath) }
            }

        case .lesson:
            let parent = parentPath(of: oldPath)
            if parentPath(of: newPath) == parent {
                updated.lessonOrder[parent] = updated.lessonOrder[parent]?.map {
                    $0 == leafName(oldPath) ? leafName(newPath) : $0
                }
            } else {
                updated.lessonOrder[parent]?.removeAll { $0 == leafName(oldPath) }
            }
        }

        return updated
    }

    private static func rewritePrefix(_ path: String, oldPath: String, newPath: String) -> String {
        if path == oldPath {
            return newPath
        }
        if path.hasPrefix(oldPath + "/") {
            return newPath + path.dropFirst(oldPath.count)
        }
        return path
    }

    private static func leafName(_ path: String) -> String {
        String(path.split(separator: "/").last ?? Substring(path))
    }

    private static func parentPath(of path: String) -> String {
        path.split(separator: "/").dropLast().joined(separator: "/")
    }
}
