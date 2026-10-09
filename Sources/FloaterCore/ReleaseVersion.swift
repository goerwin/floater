public struct ReleaseVersion: Comparable, CustomStringConvertible, Sendable {
    private let components: [Int]

    public init?(_ value: String) {
        let version = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        guard parts.count == 3, numbers.count == 3,
              numbers.allSatisfy({ $0 >= 0 }),
              zip(parts, numbers).allSatisfy({ String($0.1) == $0.0 }) else {
            return nil
        }
        components = numbers
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}
