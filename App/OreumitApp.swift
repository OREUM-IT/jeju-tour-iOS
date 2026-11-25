import SwiftUI

/// 오름잇 iOS 앱 — 웹(www.oreumit.com)의 기능은 그대로 쓰고,
/// 로그인 · 바깥 링크 · 공유 · 오프라인 · 알림 창은 앱이 직접 처리한다 (WebContainer.swift).
@main
struct OreumitApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @StateObject private var model = WebModel()

    var body: some View {
        ZStack {
            WebContainer(model: model)
            if model.offline {
                OfflineView(retry: model.reload)
            }
        }
    }
}
