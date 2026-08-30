import Foundation

public extension Notification.Name {
    /// Posted whenever the recent classrooms list changes, so UI that
    /// lives outside the view model's ownership (e.g. the File menu) can
    /// stay in sync.
    static let recentClassroomsDidChange = Notification.Name("recentClassroomsDidChange")
}
