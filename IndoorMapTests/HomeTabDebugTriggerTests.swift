#if DEBUG
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import fingerprint_library

struct HomeTabTapSequenceTests {
    @Test("홈 입력은 정확히 다섯 번째에만 열리고 다음 입력은 새 순서를 시작한다")
    func fiveTapsAndReset() {
        var sequence = HomeTabTapSequence()
        let opened = (0..<10).filter { sequence.register(isHome: true, at: Double($0) * 0.1) }
        #expect(opened == [4, 9])
    }

    @Test("다른 탭을 누르면 직전 홈 입력을 누적하지 않는다")
    func otherTabBreaksSequence() {
        var sequence = HomeTabTapSequence()
        let first = (0..<4).map { sequence.register(isHome: true, at: Double($0) * 0.1) }
        #expect(!first.contains(true))
        let other = sequence.register(isHome: false, at: 0.4)
        #expect(!other)
        let next = (5..<9).map { sequence.register(isHome: true, at: Double($0) * 0.1) }
        #expect(!next.contains(true))
        let fifth = sequence.register(isHome: true, at: 0.9)
        #expect(fifth)
    }

    @Test("1초를 넘겨 쉬거나 시간이 역행하면 이전 입력을 초기화한다")
    func pausesBreakSequence() {
        var sequence = HomeTabTapSequence()
        let first = [0.0, 0.2, 0.4, 2.0, 2.2, 2.4, 2.6].map { sequence.register(isHome: true, at: $0) }
        #expect(!first.contains(true))
        let fifth = sequence.register(isHome: true, at: 2.8)
        #expect(fifth)
        let afterClockReset = [10.0, 10.2, 10.4, 0.0, 0.2, 0.4, 0.6].map { sequence.register(isHome: true, at: $0) }
        #expect(!afterClockReset.contains(true))
        let fifthAfterClockReset = sequence.register(isHome: true, at: 0.8)
        #expect(fifthAfterClockReset)
    }
}

extension IndoorMapSerialTests {
    @MainActor
    struct HomeTabDebugTriggerTests {
        private final class TabDelegate: NSObject, UITabBarControllerDelegate { }

        @Test("이미 선택된 홈의 5회 재선택을 감지하고 기존 delegate와 기본 터치 전달을 유지한다")
        func observesReselectionWithoutReplacingDelegate() throws {
            let root = UIViewController()
            let tabs = UITabBarController()
            tabs.viewControllers = [UIViewController(), UIViewController()]
            let delegate = TabDelegate()
            tabs.delegate = delegate
            root.addChild(tabs)
            root.view.addSubview(tabs.view)
            tabs.didMove(toParent: root)
            var activations = 0
            let probe = HomeTabDebugTrigger.Controller(isEnabled: true, isHomeSelected: { tabs.selectedIndex == 0 }) {
                activations += 1
            }
            root.addChild(probe)
            root.view.addSubview(probe.view)
            probe.didMove(toParent: root)
            probe.attachIfPossible()
            defer { probe.tearDown() }
            #expect(probe.observedTabController === tabs)
            #expect(probe.tapRecognizer.view === tabs.tabBar)
            #expect(tabs.delegate === delegate)
            #expect(!probe.tapRecognizer.cancelsTouchesInView)
            #expect(!probe.tapRecognizer.delaysTouchesBegan)
            #expect(!probe.tapRecognizer.delaysTouchesEnded)
            tabs.selectedIndex = 0
            for index in 0..<4 { probe.recordCompletedTabTap(at: Double(index) * 0.1) }
            #expect(activations == 0)
            probe.recordCompletedTabTap(at: 0.4)
            #expect(activations == 1)
            for index in 5..<9 { probe.recordCompletedTabTap(at: Double(index) * 0.1) }
            tabs.selectedIndex = 1
            probe.recordCompletedTabTap(at: 0.9)
            tabs.selectedIndex = 0
            for index in 10..<14 { probe.recordCompletedTabTap(at: Double(index) * 0.1) }
            #expect(activations == 1)
            probe.isEnabled = false
            probe.recordCompletedTabTap(at: 1.4)
            probe.isEnabled = true
            for index in 20..<25 { probe.recordCompletedTabTap(at: Double(index) * 0.1) }
            #expect(activations == 2)
            probe.tearDown()
            #expect(probe.tapRecognizer.view == nil)
            #expect(tabs.delegate === delegate)
        }

        @Test("탭 컨트롤 터치는 감지하되 바 배경·검색 입력·바 밖 터치는 세지 않는다")
        func filtersNonTabTouches() {
            let bar = UITabBar()
            let button = UIButton(type: .system)
            let label = UILabel()
            button.addSubview(label)
            bar.addSubview(button)
            #expect(HomeTabDebugTrigger.Controller.isTabControlTouch(label, in: bar))
            let background = UIView()
            bar.addSubview(background)
            #expect(!HomeTabDebugTrigger.Controller.isTabControlTouch(background, in: bar))
            let field = UITextField()
            bar.addSubview(field)
            #expect(!HomeTabDebugTrigger.Controller.isTabControlTouch(field, in: bar))
            #expect(!HomeTabDebugTrigger.Controller.isTabControlTouch(UIButton(type: .system), in: bar))
        }

        @Test("실제 SwiftUI TabView 배경에서도 탭바를 찾아 숨은 감지기를 연결한다")
        func attachesToSwiftUITabView() async throws {
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let host = UIHostingController(rootView: TabView {
                Tab("홈", systemImage: "house") { Color.black }
                Tab("추천", systemImage: "books.vertical") { Color.blue }
            }.background {
                HomeTabDebugTrigger(isEnabled: true, isHomeSelected: { true }, onActivate: { })
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            })
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            var found: HomeTabDebugTrigger.Controller?
            for _ in 0..<100 {
                host.view.layoutIfNeeded()
                found = findProbe(in: host)
                if found?.observedTabController?.tabBar.window === window { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            let probe = try #require(found)
            let tabs = try #require(probe.observedTabController)
            #expect(probe.tapRecognizer.view === tabs.tabBar)
            #expect(tabs.tabBar.window === window)
            #expect(!probe.tapRecognizer.cancelsTouchesInView)
        }

        private func findProbe(in controller: UIViewController) -> HomeTabDebugTrigger.Controller? {
            if let probe = controller as? HomeTabDebugTrigger.Controller { return probe }
            for child in controller.children {
                if let found = findProbe(in: child) { return found }
            }
            return nil
        }
    }
}
#endif
