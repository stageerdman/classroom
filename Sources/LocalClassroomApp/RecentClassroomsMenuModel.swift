import Combine
import Foundation
import LocalClassroomCore

/// Mirrors `RecentClassroomStore` for the File → Open Recent menu, which
/// lives at the App/Commands level and has no direct reference to the
/// classroom view model owned deeper in the view hierarchy.
@MainActor
final class RecentClassroomsMenuModel: ObservableObject {
    @Published private(set) var recents: [RecentClassroom]

    private let store: RecentClassroomStore
    private var cancellable: AnyCancellable?

    init(store: RecentClassroomStore = RecentClassroomStore()) {
        self.store = store
        self.recents = store.list()

        cancellable = NotificationCenter.default.publisher(for: .recentClassroomsDidChange)
            .sink { [weak self] _ in
                self?.recents = self?.store.list() ?? []
            }
    }
}
