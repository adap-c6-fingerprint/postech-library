import ComposableArchitecture
import Testing

@testable import fingerprint_library

nonisolated struct FoundationModelsDependencyIsolationTests {
    @Test("메인 액터 밖에서도 모델 의존성을 주입하고 키패스로 읽을 수 있다")
    func readsDependencyFromBackground() async {
        let available = await Task.detached {
            withDependencies {
                $0.foundationModelsClient = FoundationModelsClient(
                    isAvailable: { true }, extractKeywords: { _ in [] }, rankBooks: { _ in [] })
            } operation: {
                @Dependency(\.foundationModelsClient) var model
                return model.isAvailable()
            }
        }.value
        #expect(available)
    }
}
