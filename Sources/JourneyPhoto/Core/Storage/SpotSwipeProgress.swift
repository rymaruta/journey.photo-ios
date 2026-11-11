import Foundation

/// 撮影スポットを払う画面（`SpotSwipeView`）の**続き**を端末に残す（2026-11-11）。
///
/// - `started`: 一度でも開いたか（ホームの入口の札を「行きたい n か所 · 続きから」にする）
/// - `seen`: 払った撮影スポットの鍵（`SavedSpotKey.official`）。次に開いたとき、見送った札をもう一度出さない
///   （「行きたい」にした札は `WishlistStore` の鍵で山から外れる）
///
/// 2026-11-11 判断: **端末ごと**に持つ（人ごとに分けない）。持つのは撮影スポットの鍵だけで、
/// 誰が何を選んだかではない（選んだ「行きたい」は `WishlistStore` が人ごとに持つ）。
/// 増え続けないよう新しい順に `limit` 件だけ残す。山が全部見た札で空になったら、呼び手が `resetSeen` して最初から
struct SpotSwipeProgress {

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static let startedKey = "journey-photo-spot-swipe-started"
    private static let seenKey = "journey-photo-spot-swipe-seen"
    static let limit = 600

    var started: Bool { defaults.bool(forKey: Self.startedKey) }

    func markStarted() {
        defaults.set(true, forKey: Self.startedKey)
    }

    var seen: Set<String> { Set(defaults.stringArray(forKey: Self.seenKey) ?? []) }

    /// 払った鍵を足す（並びは古い順・同じ鍵は後ろへ）
    func addSeen(_ keys: [String]) {
        let fresh = keys.filter { !$0.isEmpty }
        guard !fresh.isEmpty else { return }
        let freshSet = Set(fresh)
        var list = (defaults.stringArray(forKey: Self.seenKey) ?? []).filter { !freshSet.contains($0) }
        list.append(contentsOf: fresh)
        defaults.set(Array(list.suffix(Self.limit)), forKey: Self.seenKey)
    }

    /// 「ひとつ戻す」で戻した鍵を外す（戻した札は次も出る）
    func removeSeen(_ key: String) {
        let list = (defaults.stringArray(forKey: Self.seenKey) ?? []).filter { $0 != key }
        defaults.set(list, forKey: Self.seenKey)
    }

    func resetSeen() {
        defaults.removeObject(forKey: Self.seenKey)
    }
}
