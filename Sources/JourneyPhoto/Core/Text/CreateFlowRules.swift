import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// **「投稿」を押したらすぐ写真の一覧**（2026-11-18 owner 採用・案 B1「投稿の入口」）の決まり。
///
/// 前（2026-11-12 の #187）は、下の「投稿」で「写真を投稿／ストーリー／旅の写真から／構図」の選ぶシートが出て、
/// 「写真を投稿」を押すと投稿の画面が 0.9 秒待ってから OS の写真選びを開いていた。いまは押した瞬間に
/// 写真の一覧（`LibraryGrid`・1.1.96 でストーリーに作ったもの）が出て、下の「投稿 | ストーリー」で替わる
/// （一覧を左右に払っても替わる）。
///
/// | 写真1枚の投稿 | 押す回数 |
/// |---|---|
/// | 前 | 投稿 → 写真を投稿 →（0.9 秒）写真 → 追加 → 投稿する → 共有カードを閉じる の 6 回 |
/// | B1 だけ | 投稿 → 写真 → 投稿する → 共有カードを閉じる の 4 回 |
/// | B1＋B2（裏で送る） | 投稿 → 写真 → 投稿する の 3 回 |
///
/// 選ぶシートにあった入口は、増やさずに一覧の上と中へ移した: 「旅の写真からまとめて」「下書き n」は一覧の上の
/// チップ、「構図を重ねて撮る」はカメラの隣のマス
enum CreateFlowRules {

    /// 一覧の下の切り替え（投稿 | ストーリー）
    enum Mode: String, CaseIterable, Equatable, Identifiable {
        case post
        case story

        var id: String { rawValue }
    }

    /// 写真1枚を投稿するまでの押す回数（上の表・`CreateFlowTapCountTests` が数える）
    static let tapsBefore = 6
    static let tapsWithLibrary = 4
    static let tapsWithBackgroundSend = 3

    /// 上の見出し（案 B1: 「新規投稿」「新しいストーリー」）
    static func title(_ mode: Mode) -> String {
        switch mode {
        case .post: return L("新規投稿", "New post")
        case .story: return L("新しいストーリー", "New story")
        }
    }

    /// 下の切り替えの字
    static func segmentTitle(_ mode: Mode) -> String {
        switch mode {
        case .post: return L("投稿", "Post")
        case .story: return L("ストーリー", "Story")
        }
    }

    /// 切り替えの道しるべ（UI テスト）。**前の選ぶシートの識別子を引き継ぐ**（投稿＝`post.choice.photo`、
    /// ストーリー＝`post.choice.story`）——ストーリーへ移る試験の手はそのまま通る
    static func segmentIdentifier(_ mode: Mode) -> String {
        switch mode {
        case .post: return "post.choice.photo"
        case .story: return "post.choice.story"
        }
    }

    // MARK: - 払う

    /// 横に払ったと見なす距離（案 B1 の模型と同じ 40pt）
    static let swipeDistance: CGFloat = 40

    /// 一覧を払ったときの行き先。**横に 40pt 以上、かつ縦より横に大きく動いたときだけ**（縦の送りを奪わない）。
    /// 左へ払う（dx < 0）とストーリー、右へ払うと投稿。同じなら nil（替えない）
    ///
    /// 🔴 **一覧の上のチップの行で始まった指は数えない**（`startsInChips`・2026-11-18 確かめ役の指摘）。チップの行は横に送れるので、
    /// 送っただけで投稿とストーリーが替わってしまう
    static func swiped(from mode: Mode, dx: CGFloat, dy: CGFloat, startsInChips: Bool = false) -> Mode? {
        guard !startsInChips else { return nil }
        guard abs(dx) >= swipeDistance, abs(dx) > abs(dy) else { return nil }
        let next: Mode = dx < 0 ? .story : .post
        return next == mode ? nil : next
    }

    // MARK: - 寸法（案 B1 の模型）

    /// 下のガラスのカプセル（幅 220・高さ 48・角 24）と、選んでいる側の札（高さ 40・#2C2C2E）
    static let capsuleWidth: CGFloat = 220
    static let capsuleHeight: CGFloat = 48
    static let capsuleInset: CGFloat = 4
    /// カプセルの下の余白（画面の下の端から。模型の 34 は家の印の帯を含むので、安全域の上は 8）
    static let capsuleBottomGap: CGFloat = 8
    /// 上の見出しの行の高さ（閉じる・選択の 44 に合わせる）。
    /// 2026-11-18 判断（owner 採用の模型 B1 どおり）: 一覧の段の題は **SF 600 17**（`.headline`）。板の決まり（見出しは明朝）とは
    /// ずれるが、owner が採った模型の寸法を正とした（シートのナビの題と同じ段）
    static let headerHeight: CGFloat = 44

    /// 印の上限（投稿は1回に扱う枚数・ストーリーは並べられる本数）
    static func markLimit(_ mode: Mode) -> Int {
        switch mode {
        case .post: return UploadViewModel.maxSelection
        case .story: return StoryQueue.maxShots
        }
    }

    /// 一覧の段で、切り替え（カプセル）を出すか。**一覧を見ている間だけ**——欄を書く・作る段では替えさせない
    /// （書きかけの投稿を、払っただけで失わない）。ログインの画面でも出す（どちらでもログインが要る）
    static func showsSwitcher(libraryShown: Bool) -> Bool { libraryShown }

    // MARK: - 一覧の上のチップ

    /// 一覧の上に出す入口（前の選ぶシートの行を、チップにして持ってきた）
    enum Entry: Equatable {
        /// 旅の写真からまとめて（投稿の入口から開いたときだけ）
        case trip
        /// 下書き n（1件以上あるとき）
        case drafts(Int)
    }

    /// 出すチップ。旅の写真からは入口から開いたときだけ（テーマ・観光スポットから開いた投稿の画面では出さない）
    static func entries(inCreateFlow: Bool, drafts: Int) -> [Entry] {
        var list: [Entry] = []
        if inCreateFlow { list.append(.trip) }
        if drafts > 0 { list.append(.drafts(drafts)) }
        return list
    }
}
