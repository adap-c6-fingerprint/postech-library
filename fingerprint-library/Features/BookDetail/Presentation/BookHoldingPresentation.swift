/// 조회한 소장처 전체를 보존하면서 상세 화면에 표시할 대표 항목만 선택한다.
nonisolated enum BookHoldingPresentation {
    static func preferred(in holdings: [BookHolding]) -> BookHolding? {
        func rank(_ holding: BookHolding) -> Int {
            switch holding.availability {
            case "available": return 0
            case "unavailable": return 2
            default: return 1
            }
        }
        return holdings.enumerated().min {
            (rank($0.element), $0.element.callNumber == nil ? 1 : 0, $0.offset)
                < (rank($1.element), $1.element.callNumber == nil ? 1 : 0, $1.offset)
        }?.element
    }
}
