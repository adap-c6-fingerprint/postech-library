import SwiftUI
import ComposableArchitecture

struct HomeView: View {
    @Bindable var store: StoreOf<HomeFeature>
    @State private var recommendationPosition: Int? = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    recommendationSection
                    popularBooksSection
                }
                .padding(.top, 22)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color(uiColor: .systemBackground))
        .toolbar(.hidden, for: .navigationBar)
        .task { store.send(.task) }
        .task(id: upcomingCoverURLs) {
            await BookCoverPipeline.shared.prefetch(upcomingCoverURLs)
        }
        .navigationDestination(
            item: $store.scope(state: \.detail, action: \.detail)
        ) { detailStore in
            BookDetailView(store: detailStore)
                .toolbar(.visible, for: .navigationBar)
        }
    }
    
    private var header: some View {
        HStack(spacing: 4) {
            Text("추천")
                .font(.system(size: 28, weight: .bold))
            
            Spacer()
            
            headerButton("cart", label: "책바구니", action: .basketButtonTapped)
            headerButton("person", label: "마이페이지", action: .profileButtonTapped)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
    }

    private var upcomingCoverURLs: [URL] {
        let nextIndex = max(0, (recommendationPosition ?? 0) + 1)
        return store.recommendedBooks.dropFirst(nextIndex).prefix(2).compactMap(\.imageURL)
    }
    
    private var recommendationSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom) {
                Text("당신에게\n추천하는 책 \(store.recommendationCount)선.")
                    .font(.system(size: 18, weight: .medium))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
                
                HStack(spacing: 0) {
                    recommendationButton(direction: -1)
                    recommendationButton(direction: 1)
                }
            }
            .padding(.horizontal, 16)
            
            if store.recommendedBooks.isEmpty {
                if store.isLoadingRecommendations || store.recommendationSessionID == nil {
                    VStack(spacing: 8) {
                        ProgressView("추천 도서를 준비하고 있어요")
                        Text("처음에는 잠시 걸릴 수 있어요.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 206)
                }
            } else {
                recommendationCarousel
            }

            if let message = store.recommendationErrorMessage {
                VStack(alignment: .leading, spacing: 10) {
                    Label(message, systemImage: "exclamationmark.circle")
                    if !store.recommendedBooks.isEmpty {
                        Text("이전 추천은 계속 볼 수 있어요.")
                            .font(.footnote)
                    }
                    Button("다시 시도") { store.send(.retryRecommendationsButtonTapped) }
                        .buttonStyle(.bordered)
                        .disabled(store.isPreparingRecommendations)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
            }
        }
    }

    private var recommendationCarousel: some View {
        ZStack(alignment: .bottom) {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .bottom, spacing: 12) {
                        ForEach(0..<store.recommendationCount, id: \.self) { index in
                            let book = store.recommendedBooks.isEmpty
                            ? nil : store.recommendedBooks[index]
                            
                            Button {
                                if let book { store.send(.bookSelected(book)) }
                            } label: {
                                HomeBookCover(book: book, width: 122, height: 180)
                            }
                            .buttonStyle(.plain)
                            .disabled(book == nil)
                            .accessibilityLabel(book?.title ?? "추천 도서 자리")
                            .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 32, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $recommendationPosition, anchor: .leading)
                .padding(.bottom, 26)
            }
            .frame(height: 206)
            .onChange(of: store.recommendedBooks.map(\.id)) { _, _ in
                recommendationPosition = 0
            }
    }
    
    private var popularBooksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                store.send(.popularBooksButtonTapped)
            } label: {
                HStack(spacing: 12) {
                    Text("‘\(store.departmentName)’에서 많이 빌린")
                        .font(.system(size: 18, weight: .semibold))
                        .multilineTextAlignment(.leading)
                    
                    Spacer(minLength: 0)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundStyle(.primary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(true) // TODO: AppFeature의 전체 보기 화면 연결 후 활성화
            .padding(.horizontal, 16)
            
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    if store.popularBooks.isEmpty {
                        ForEach(0..<4, id: \.self) { _ in
                            HomePopularBookCard(book: nil, libraryInfo: nil)
                                .accessibilityLabel("인기 도서 자리")
                        }
                    } else {
                        ForEach(store.popularBooks) { book in
                            Button {
                                store.send(.bookSelected(book))
                            } label: {
                                HomePopularBookCard(
                                    book: book,
                                    libraryInfo: store.libraryInfo[book.id]
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("책 소개 보기")
                        }
                    }
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollIndicators(.hidden)
        }
    }
    
    private func headerButton(
        _ symbol: String,
        label: String,
        action: HomeFeature.Action
    ) -> some View {
        Button { store.send(action) } label: {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(true) // TODO: AppFeature의 목적 화면 연결 후 활성화
        .accessibilityLabel(label)
    }
    
    private func recommendationButton(direction: Int) -> some View {
        let position = recommendationPosition ?? 0
        let target = min(max(position + direction, 0), store.recommendationCount - 1)
        
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                recommendationPosition = target
            }
        } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 36, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .disabled(target == position)
        .accessibilityLabel(direction < 0 ? "이전 추천 도서" : "다음 추천 도서")
    }
}

private struct HomeBookCover: View {
    let book: Book?
    let width: CGFloat
    let height: CGFloat
    
    var body: some View {
        // 홈 카드는 전체가 상세 이동 버튼이다. 재시도는 열린 상세 화면에서 제공한다.
        BookCoverView(url: book?.imageURL, allowsRetry: false)
        .frame(width: width, height: height)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityHidden(true)
    }
}

private struct HomePopularBookCard: View {
    let book: Book?
    let libraryInfo: HomeFeature.LibraryInfo?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeBookCover(book: book, width: 96, height: 140)
                .padding(.bottom, 8)
            
            if let book {
                Text(book.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text(book.author)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                placeholder(width: 88, height: 14)
                placeholder(width: 76, height: 10)
            }
            
            if let location = libraryInfo?.location {
                Text(location)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                placeholder(width: 86, height: 10)
            }
            
            if let isAvailable = libraryInfo?.isAvailable {
                Text(isAvailable ? "대출 가능" : "대출 불가")
                    .font(.system(size: 12))
                    .foregroundStyle(isAvailable ? Color.green : Color.red)
            } else {
                placeholder(width: 48, height: 10)
            }
        }
        .frame(width: 96, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
    
    private func placeholder(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(.primary.opacity(0.10))
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

#Preview("추천 홈 · 다크") {
    NavigationStack {
        HomeView(store: Store(initialState: HomeFeature.State()) { HomeFeature() })
    }
    .preferredColorScheme(.dark)
}
