import ClassroomCore
import SwiftUI

struct DeveloperScannerView: View {
    @State private var folderPath = ""
    @State private var hierarchyText = "Enter a classroom folder path."

    private let viewModel = DeveloperScannerViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Developer Parser")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("Classroom folder path", text: $folderPath)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(scan)

                Button("Scan", action: scan)
                    .keyboardShortcut(.return, modifiers: [.command])
            }

            ScrollView {
                Text(hierarchyText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(minHeight: 220)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func scan() {
        hierarchyText = viewModel.parseHierarchyText(path: folderPath)
    }
}
