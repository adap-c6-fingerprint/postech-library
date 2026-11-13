//
//  BinaryHeap.swift
//  Fingerprint
//
//  Created by Codex on 9/29/26.
//

import Foundation

nonisolated struct BinaryHeap<Element> {
    private var elements: [Element] = []
    private let hasHigherPriority: (Element, Element) -> Bool

    init(hasHigherPriority: @escaping (Element, Element) -> Bool) {
        self.hasHigherPriority = hasHigherPriority
    }

    var isEmpty: Bool { elements.isEmpty }
    var count: Int { elements.count }
    var peek: Element? { elements.first }

    mutating func insert(_ element: Element) {
        elements.append(element)
        siftUp(from: elements.count - 1)
    }

    mutating func pop() -> Element? {
        guard !elements.isEmpty else { return nil }
        guard elements.count > 1 else { return elements.removeLast() }

        elements.swapAt(0, elements.count - 1)
        let result = elements.removeLast()
        siftDown(from: 0)
        return result
    }

    private mutating func siftUp(from index: Int) {
        var child = index

        while child > 0 {
            let parent = (child - 1) / 2
            guard hasHigherPriority(elements[child], elements[parent]) else { return }
            elements.swapAt(child, parent)
            child = parent
        }
    }

    private mutating func siftDown(from index: Int) {
        var parent = index

        while true {
            let left = parent * 2 + 1
            let right = left + 1
            var candidate = parent

            if left < elements.count,
               hasHigherPriority(elements[left], elements[candidate]) {
                candidate = left
            }
            if right < elements.count,
               hasHigherPriority(elements[right], elements[candidate]) {
                candidate = right
            }
            guard candidate != parent else { return }

            elements.swapAt(parent, candidate)
            parent = candidate
        }
    }
}
