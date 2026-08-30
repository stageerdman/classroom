import ClassroomCore
import SwiftUI

struct ClassroomGalleryView: View {
    let classroomName: String
    let modules: [GalleryModule]
    let onOpenModule: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 20)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(classroomName)
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 32)
                    .padding(.top, 24)

                if modules.isEmpty {
                    ContentUnavailableView(
                        "No Modules",
                        systemImage: "rectangle.stack",
                        description: Text("Add a module folder inside this classroom to get started.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(modules) { module in
                            ModuleCardView(module: module)
                                .onTapGesture { onOpenModule(module.id) }
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ModuleCardView: View {
    let module: GalleryModule

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(module.name)
                .font(.headline)
                .fontWeight(.bold)
                .lineLimit(2)

            if let description = module.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: module.progress.percentage)
                Text("\(module.progress.completedLessons)/\(module.progress.totalLessons) complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(minHeight: 160, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .contentShape(Rectangle())
    }
}
