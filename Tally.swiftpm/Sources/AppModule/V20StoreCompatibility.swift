import Foundation

extension TallyStore {
    func setExactValue(_ counter: TallyCounter, to value: Int) {
        guard let index = counters.firstIndex(where: { $0.id == counter.id }),
              !counters[index].isLocked else { return }
        let before = counters[index].value
        counters[index].value = value
        counters[index].updatedAt = Date()
        history.insert(
            TallyHistoryEntry(
                counterID: counter.id,
                counterName: counters[index].name,
                action: "Set Value",
                delta: value - before,
                beforeValue: before,
                afterValue: value
            ),
            at: 0
        )
    }
}
