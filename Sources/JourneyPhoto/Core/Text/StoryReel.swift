import Foundation

/// ストーリーの**人から人への並び**（2026-09-29・owner「ストーリー機能最強にして欲しい」
/// 「インスタ超えたい」）。閲覧画面（`StoryViewerView`）は1人の束だけを見る。
/// その外側で、輪の並び（自分 → 未読 → 既読）の順に**次の人へ進む**。
///
/// 以前は1人の最後まで見ると閉じていた。Web 版（`StoryViewer.tsx`）は次の人へ進む。
///
/// 動きは立方体（隣の面へ回る）。決まりはここに置き、画面（`StoryReelView`）は描くだけ
enum StoryReel {

    /// 1人ぶんの束と、最初に開く位置
    struct Group: Equatable {
        let stories: [Story]
        let start: Int
    }

    /// 輪の並び（`StoryPlayback.orderedRings` の自分＋ほか）から、人ごとの束を作る。
    /// 各束は**輪に出していた1本から**開く（輪を押したときと同じ）
    static func groups(rings: [Story], in all: [Story]) -> [Group] {
        var seen = Set<String>()
        return rings.compactMap { ring in
            let group = StoryPlayback.siblings(of: ring, in: all)
            guard !group.stories.isEmpty,
                  let first = group.stories.first,
                  seen.insert(first.id).inserted else { return nil }
            return Group(stories: group.stories, start: group.index)
        }
    }

    /// 束から、もう見せない1本（通報・削除）と**ブロックした人**を外す。
    /// 残りが無ければ nil（その人は並びから飛ばす）。開く位置は元の1本が残っていれば
    /// そこ、消えていれば先頭
    static func live(_ group: Group, removed: Set<String>, blocked: Set<String>) -> Group? {
        let kept = group.stories.filter { story in
            !removed.contains(story.id) && !(story.userId.map { blocked.contains($0) } ?? false)
        }
        guard !kept.isEmpty else { return nil }
        let startId = group.stories.indices.contains(group.start) ? group.stories[group.start].id : nil
        let start = kept.firstIndex { $0.id == startId } ?? 0
        return Group(stories: kept, start: start)
    }

    /// `from` から `step`（+1 / -1）の向きで、**まだ見せるものがある**いちばん近い人
    static func neighbor(from index: Int, step: Int, count: Int, isLive: (Int) -> Bool) -> Int? {
        guard step != 0 else { return nil }
        var i = index + step
        while i >= 0, i < count {
            if isLive(i) { return i }
            i += step
        }
        return nil
    }

    // MARK: - 立方体

    /// 面の回り（度）。`minX` は面の左端の位置（画面の左端が 0、右隣の面は `width`）。
    /// **画面の真ん中の面は 0 度、隣の面は ±90 度**——指に付いて 0 から ±90 へ回る
    static func cubeAngle(minX: Double, width: Double) -> Double {
        guard width > 0 else { return 0 }
        return max(-90, min(90, minX / width * 90))
    }

    /// 面の回りの軸。**右へずれた面は左端、左へずれた面は右端**を軸にする
    /// （2つの面が境目で接して回る＝立方体）
    enum Hinge: Equatable { case leading, trailing }

    static func hinge(minX: Double) -> Hinge {
        minX > 0 ? .leading : .trailing
    }

    // MARK: - 指を離したとき

    enum Release: Equatable {
        /// 次の人へ回りきる
        case forward
        /// 前の人へ回りきる
        case back
        /// 元の面へ戻る
        case stay
    }

    /// 回りきるのに要る移動（画面の幅に対する割合）
    static let turnFraction: Double = 0.25

    /// 横に払って離したとき。**勢い（`predictedDX`）でも決める**——短く速く払えば回る。
    /// 隣の人がいない向きは戻す（最初の人から右へ・最後の人から左へ）。
    /// **勢いは引いている向きと同じときだけ使う**——左へ引いて（次の人が見えている）
    /// 最後に右へ弾くと、見えていない前の人へ回っていた
    static func release(dx: Double, predictedDX: Double, width: Double,
                        hasNext: Bool, hasPrevious: Bool) -> Release {
        guard width > 0 else { return .stay }
        let limit = width * turnFraction
        let sameDirection = dx == 0 || (dx < 0) == (predictedDX < 0)
        let travel = sameDirection && abs(predictedDX) > abs(dx) ? predictedDX : dx
        if travel <= -limit, hasNext { return .forward }
        if travel >= limit, hasPrevious { return .back }
        return .stay
    }

    /// 隣の人がいない向きへは**重く**しか動かない（端に当たった手応え）
    static func resisted(dx: Double, hasNext: Bool, hasPrevious: Bool) -> Double {
        if dx < 0, !hasNext { return dx / 3 }
        if dx > 0, !hasPrevious { return dx / 3 }
        return dx
    }

    // MARK: - 縦横の決め方

    enum Axis: Equatable { case horizontal, vertical }

    /// これ未満は向きを決めない（指の揺れ）
    static let axisThreshold: Double = 10

    /// 払い始めの向き。**一度決めたら離すまで変えない**（斜めに揺れて回りながら縮む、を防ぐ）。
    /// 上へは何もしない（`StoryPlayback.swipe` と同じ）
    static func axis(dx: Double, dy: Double) -> Axis? {
        let ax = abs(dx), ay = abs(dy)
        guard max(ax, ay) >= axisThreshold else { return nil }
        if ax >= ay { return .horizontal }
        return dy > 0 ? .vertical : nil
    }

    // MARK: - 下へ払って閉じる

    /// これだけ下へ引いて離したら閉じる（勢いでも閉じる）
    static let closeDistance: Double = 120

    static func closes(dy: Double, predictedDY: Double) -> Bool {
        max(dy, predictedDY) >= closeDistance
    }

    /// 下へ引いている間の縮み（1 → 0.8）。**指に付いて小さくなる**
    static func dragScale(dy: Double) -> Double {
        1 - min(max(dy, 0), 400) / 2000
    }
}
