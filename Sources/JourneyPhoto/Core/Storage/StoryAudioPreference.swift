import Foundation

/// ストーリーの音を消したか。**一度消したら、次の1本・次に開いたときも消したまま**
/// （2026-09-30・owner「iOS のストーリー機能大好きだからもっと作り込みたい」）。
///
/// 以前は閲覧画面の `@State`（既定は音あり）だけで、人が替わる・開き直すたびに音ありに
/// 戻っていた。**端末ごと**に覚える（人の好みで、アカウントの中身ではない——ログアウトで
/// 消す `AccountLocalData` の対象にしない）
struct StoryAudioPreference {

    static let key = "journey-photo-story-muted"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 消しているか。**覚えが無ければ音あり**（今までと同じ）
    var muted: Bool {
        get { defaults.bool(forKey: Self.key) }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }
}
