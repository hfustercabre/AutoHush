/// An element of a list with an identity that outlives its place: its key,
/// and how many before it share that key (0 for the first).
struct Keyed<Key: Hashable, Element>: Identifiable {
    struct ID: Hashable {
        let key: Key
        let occurrence: Int
    }

    let id: ID
    /// Its place in the list.
    let offset: Int
    let element: Element
}

extension Array {
    /// The elements identified by `key`, for a `ForEach` over a list whose
    /// elements come and go: the rows that stay keep their identity, unlike
    /// by position. Elements sharing a key are told apart by their order
    /// among themselves.
    func keyed<Key: Hashable>(by key: (Element) -> Key) -> [Keyed<Key, Element>] {
        var seen: [Key: Int] = [:]
        return enumerated().map { offset, element in
            let key = key(element)
            let occurrence = seen[key, default: 0]
            seen[key] = occurrence + 1
            return Keyed(id: .init(key: key, occurrence: occurrence), offset: offset, element: element)
        }
    }
}
