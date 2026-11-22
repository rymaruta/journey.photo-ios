import Foundation
import Combine

/// 起動したときに「新しくなったこと」を出すか（決まりは `WhatsNew.pending`）。
///
/// **作った時点（＝起動した時点）で決める。** 規約の画面で同意した後に決めると、
/// 新しくインストールした人まで「前から使っていた」に見える。`RootView` の `@StateObject`
/// なので、起動で1回だけ作られる。
///
/// 2026-11-22 判断（札 #628）: ホームの印（`WhatsNewHomeBadge`）も同じ門を見るので、起動で1つだけ作る `shared` にした。
/// 印は読むまで残り、次の版の分は「見た版より後」として足されていく（`WhatsNew.pending`）
@MainActor
final class WhatsNewGate: ObservableObject {

    /// 起動で1回だけ作る（`RootView` の初期化で最初に読む＝規約の同意より前に決まる）
    static let shared = WhatsNewGate()

    /// 見た版の鍵。UI テストは起動の引数（`-whatsNew.seenVersion 0.0.1`）で更新後を作る
    nonisolated static let seenKey = "whatsNew.seenVersion"
    /// 規約の同意の鍵（`LegalConsent`）。「前に開いたことがある」の目印に読むだけ
    nonisolated static let consentKey = "legal.consent.version"

    /// 出す版（新しい順）。出したら空にする
    @Published private(set) var pending: [WhatsNew.Release]

    private let defaults: UserDefaults
    private let current: String

    /// まだ読んでいない項目がある（ホームの印を出す）
    var shouldPresent: Bool { !pending.isEmpty }

    /// 起動のときの出し方（印だけか、シートか・`WhatsNew.launchPresentation`）
    var presentation: WhatsNew.LaunchPresentation { WhatsNew.launchPresentation(pending) }

    init(defaults: UserDefaults = .standard,
         current: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
         releases: [WhatsNew.Release]? = nil) {
        self.defaults = defaults
        self.current = current
        let seen = defaults.string(forKey: Self.seenKey)
        let usedBefore = defaults.integer(forKey: Self.consentKey) > 0
        pending = WhatsNew.pending(releases: releases ?? WhatsNew.bundled(),
                                   seen: seen, current: current, usedBefore: usedBefore)
        // 新しいインストール・同じ版・新しい項目の無い更新: いまの版を覚えて終わり
        // （覚えないと、次の更新で「この仕組みより前の人」と同じ扱いになる）
        if pending.isEmpty, !current.isEmpty { defaults.set(current, forKey: Self.seenKey) }
    }

    /// 出した。いまの版を覚え、この起動ではもう出さない
    func markSeen() {
        if !current.isEmpty { defaults.set(current, forKey: Self.seenKey) }
        pending = []
    }
}
