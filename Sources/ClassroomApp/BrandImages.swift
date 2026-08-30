import AppKit
import SwiftUI

enum BrandImage {
    case icon
    case wordmark

    private var resourceName: String {
        switch self {
        case .icon: "classroom-icon"
        case .wordmark: "classroom-wordmark"
        }
    }

    var image: Image? {
        guard
            let url = Bundle.module.url(forResource: resourceName, withExtension: "png"),
            let nsImage = NSImage(contentsOf: url)
        else {
            return nil
        }

        return Image(nsImage: nsImage)
    }
}
