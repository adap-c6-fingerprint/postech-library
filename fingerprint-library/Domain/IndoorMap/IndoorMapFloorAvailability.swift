extension IndoorMap {
    /// 현재 서비스에서 선택할 수 있는 3·4층. 원본 도면의 전체 층 정보는 보존한다.
    var selectableFloors: [IndoorMapFloor] {
        floors.filter { $0.ordinal == 2 || $0.ordinal == 3 }
    }

    /// 지원하는 현재 층을 우선하고, 위치가 없거나 지원하지 않는 층이면 3층부터 표시한다.
    func initialDisplayFloor(reportedOrdinal: Int?) -> IndoorMapFloor? {
        let available = selectableFloors
        return available.first { $0.ordinal == reportedOrdinal } ?? available.first
    }
}
