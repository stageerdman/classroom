import LocalClassroomCore
import SwiftUI

@main
struct LocalClassroomApp: App {
    @StateObject private var recentClassroomsMenuModel = RecentClassroomsMenuModel()

    var body: some Scene {
        WindowGroup("Local Classroom") {
            HomeView()
        }
        .commands {
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
        }
    }
}

extension Notification.Name {
    static let openClassroomRequested = Notification.Name("openClassroomRequested")
    static let openRecentClassroomRequested = Notification.Name("openRecentClassroomRequested")
    static let refreshClassroomRequested = Notification.Name("refreshClassroomRequested")
}
