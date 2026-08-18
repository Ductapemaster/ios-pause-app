public struct SelectionChange<ID: Hashable & Sendable>: Equatable, Sendable {
    public let added: Set<ID>
    public let retained: Set<ID>
    public let removed: Set<ID>

    public init(added: Set<ID>, retained: Set<ID>, removed: Set<ID>) {
        self.added = added
        self.retained = retained
        self.removed = removed
    }
}

public func selectionChange<ID: Hashable & Sendable>(
    existing: Set<ID>,
    selected: Set<ID>
) -> SelectionChange<ID> {
    SelectionChange(
        added: selected.subtracting(existing),
        retained: existing.intersection(selected),
        removed: existing.subtracting(selected)
    )
}
