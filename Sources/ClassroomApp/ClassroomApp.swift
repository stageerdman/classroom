import ClassroomCore
import SwiftUI

@main
struct ClassroomApp: App {
    @StateObject private var recentClassroomsMenuModel = RecentClassroomsMenuModel()
    @State private var blockNoteSpikeWindowController = BlockNoteSpikeWindowController()

    var body: some Scene {
        WindowGroup("Classroom") {
            HomeView()
        }
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("BlockNote Spike (Dev)") {
                    blockNoteSpikeWindowController.present()
                }
            }

            CommandGroup(after: .newItem) {
                Button("Open Classroom...") {
                    NotificationCenter.default.post(name: .openClassroomRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])

                Menu("Open Recent") {
                    if recentClassroomsMenuModel.recents.isEmpty {
                        Text("No Recent Classrooms")
                    } else {
                        ForEach(recentClassroomsMenuModel.recents) { recent in
                            Button(recent.name) {
                                NotificationCenter.default.post(
                                    name: .openRecentClassroomRequested,
                                    object: nil,
                                    userInfo: ["path": recent.path]
                                )
                            }
                        }
                    }
                }

                Button("Refresh Classroom") {
                    NotificationCenter.default.post(name: .refreshClassroomRequested, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])
            }

            // Replaces SwiftUI's default (inert, since this app doesn't use
            // the environment's \.undoManager) Undo/Redo menu items with
            // ones wired to ClassroomBrowserViewModel's own undo stack via
            // the same NotificationCenter pattern used above — there's only
            // ever one open classroom/window, so a broadcast is enough.
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    NotificationCenter.default.post(name: .undoEditRequested, object: nil)
                }
                .keyboardShortcut("z", modifiers: [.command])

                Button("Redo") {
                    NotificationCenter.default.post(name: .redoEditRequested, object: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let openClassroomRequested = Notification.Name("openClassroomRequested")
    static let openRecentClassroomRequested = Notification.Name("openRecentClassroomRequested")
    static let refreshClassroomRequested = Notification.Name("refreshClassroomRequested")
    static let undoEditRequested = Notification.Name("undoEditRequested")
    static let redoEditRequested = Notification.Name("redoEditRequested")
}
