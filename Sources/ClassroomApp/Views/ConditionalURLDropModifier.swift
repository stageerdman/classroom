import SwiftUI

/// Only registers as a drop target when `isEnabled` — outside edit mode
/// the view underneath behaves exactly as it always has.
struct ConditionalURLDropModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var isTargeted: Bool
    let action: ([URL]) -> Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.dropDestination(for: URL.self) { urls, _ in
                action(urls)
            } isTargeted: { isTargeted = $0 }
        } else {
            content
        }
    }
}
