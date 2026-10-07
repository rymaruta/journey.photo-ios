import Foundation
import Combine

/// うれしい瞬間を数え、評価をお願いする頃合いを `RootView` に伝える（決まりは `ReviewPrompt`）。
///
/// **回数で伝える**（`requests`）。真偽値にすると、2回目に立てても「変わっていない」と
/// 見なされて届かない（`TabRouter` と同じ理由）。数えた値・前にお願いした版と日は
/// 端末にだけ置く（サーバーに送らない）。
///
/// 絵を撮るための入り方（`PreviewSession`・UI テスト）では数えない——巡回の途中で
/// OS の評価の札が出て、画面の絵を覆わないように
@MainActor
final class ReviewPromptStore: ObservableObject {

    static let shared = ReviewPromptStore()

    /// お願いしてよい頃合いになった回数（`RootView` がこれを見て、ほかの画面が閉じてから頼む）
    @Published private(set) var requests = 0

    private enum Keys {
        static let happyMoments = "reviewPrompt.happyMoments"
        static let lastAskedVersion = "reviewPrompt.lastAskedVersion"
        static let lastAskedAt = "reviewPrompt.lastAskedAt"
    }

    private let defaults: UserDefaults
    private let currentVersion: () -> String
    private let now: () -> Date
    private let isPreview: () -> Bool

    init(defaults: UserDefaults = .standard,
         currentVersion: @escaping () -> String = {
             Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
         },
         now: @escaping () -> Date = Date.init,
         isPreview: @escaping () -> Bool = { PreviewSession.userId != nil }) {
        self.defaults = defaults
        self.currentVersion = currentVersion
        self.now = now
        self.isPreview = isPreview
    }

    /// たまっている、うれしい瞬間の数
    var happyMoments: Int { defaults.integer(forKey: Keys.happyMoments) }

    /// いまお願いしてよいか
    var shouldAsk: Bool {
        ReviewPrompt.shouldAsk(happyMoments: happyMoments, currentVersion: currentVersion(),
                               lastAskedVersion: defaults.string(forKey: Keys.lastAskedVersion),
                               lastAskedAt: defaults.object(forKey: Keys.lastAskedAt) as? Date,
                               now: now())
    }

    /// うれしい瞬間を1つ数える（投稿が全部上がった・「行きたい」に入れた）
    func noteHappyMoment() {
        guard !isPreview() else { return }
        defaults.set(happyMoments + 1, forKey: Keys.happyMoments)
        if shouldAsk { requests += 1 }
    }

    /// これからお願いする。**お願いしてよいときだけ** true を返し、版と日を覚えて数を戻す
    /// （OS が実際に札を出したかは分からないので、頼んだ時点で覚える）
    @discardableResult
    func consume() -> Bool {
        guard shouldAsk else { return false }
        defaults.set(currentVersion(), forKey: Keys.lastAskedVersion)
        defaults.set(now(), forKey: Keys.lastAskedAt)
        defaults.set(0, forKey: Keys.happyMoments)
        return true
    }
}
