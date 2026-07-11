import Foundation

public enum NaturalSort {
    public static func sorted<T>(_ values: [T], by keyPath: KeyPath<T, String>) -> [T] {
        values.sorted { left, right in
            left[keyPath: keyPath].localizedStandardCompare(right[keyPath: keyPath]) == .orderedAscending
        }
    }

    public static func sorted(_ values: [String]) -> [String] {
        values.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }
}
