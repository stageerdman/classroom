public struct GalleryModule: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let description: String?
    public let progress: ProgressSummary

    public init(id: String, name: String, description: String?, progress: ProgressSummary) {
        self.id = id
        self.name = name
        self.description = description
        self.progress = progress
    }
}
