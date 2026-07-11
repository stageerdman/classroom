import SwiftUI

@main
struct LocalClassroomApp: App {
    var body: some Scene {
        WindowGroup("") {
            HomeView()
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Classroom...") {
                    NotificationCenter.default.post(name: .openClassroomRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])

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
    static let refreshClassroomRequested = Notification.Name("refreshClassroomRequested")
}
