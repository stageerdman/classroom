import Foundation

public enum OrderingService {
    public static func ordered<T>(
        _ values: [T],
        savedOrder: [String],
        id: (T) -> String,
        naturalKey: (T) -> String
    ) -> [T] {
        let byID = Dictionary(uniqueKeysWithValues: values.map { (id($0), $0) })
        let savedValues = savedOrder.compactMap { byID[$0] }
        let savedIDs = Set(savedOrder)
        let newValues = values.filter { !savedIDs.contains(id($0)) }

        return savedValues + newValues.sorted {
            naturalKey($0).localizedStandardCompare(naturalKey($1)) == .orderedAscending
        }
    }

    public static func moved(_ order: [String], from source: IndexSet, to destination: Int) -> [String] {
        var updated = order
        let movingValues = source.sorted().map { updated[$0] }

        for index in source.sorted(by: >) {
            updated.remove(at: index)
        }

        let removedBeforeDestination = source.filter { $0 < destination }.count
        let insertionIndex = max(0, min(updated.count, destination - removedBeforeDestination))
        updated.insert(contentsOf: movingValues, at: insertionIndex)
        return updated
    }

    public static func orderAfterMoving(id: String, in order: [String], offset: Int) -> [String] {
        guard
            let index = order.firstIndex(of: id),
            order.indices.contains(index + offset)
        else {
            return order
        }

        var updated = order
        updated.swapAt(index, index + offset)
        return updated
    }
}
