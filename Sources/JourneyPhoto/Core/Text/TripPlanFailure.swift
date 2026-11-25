import Foundation

/// 旅行プランの画面の失敗（2026-11-25 判断・人間工学の案 2）。
///
/// 前は5つの窓（`.alert`）で出していた: 「保存できませんでした」「ひとことを入れられませんでした」「動かせませんでした」
/// 「共有できませんでした」「削除できませんでした」。どれも OK しかなく、直すには OK → 「…」→ 操作をし直す、の3回が要った。
/// 窓が出ている間は画面が止まり、旅先の圏外では何度も止まった。
///
/// 今は**画面の下に帯を1本**（デザインの板の「状態の帯」`JPStateBand`）。画面は止めずに、指の近くの「もう一度」1回で直す。
/// 帯は払うか、直るまで残す（6秒で消える知らせより長く）。電波が無いときは「電波が戻ったら押してください」と添える。
/// 項目が変わって入れられなかった・動かせなかった回（もう一度しても同じ結果になる）は「もう一度」を出さず「閉じる」にする。
///
/// ひとことを書く欄（窓の中の入力欄）は入力なので、このまま（案の頁のとおり）
struct TripPlanFailure: Equatable {

    enum Kind: Equatable {
        /// 「保存して戻る」が送れなかった（もう一度で、送ってから戻る）
        case save
        /// 書いている間に項目が変わり、ひとことを入れられなかった
        case note
        /// メニューを開いている間に項目が変わり、動かせなかった
        case move
        /// 共有（仲間を誘う）が断られた・送れなかった
        case share
        /// 削除・抜けるが断られた・送れなかった
        case delete
    }

    let kind: Kind
    /// 何が起きたか（窓の説明に出していた文）
    let detail: String
    /// 出すたびに進む印（同じ失敗が続いても、帯を出し直して読み上げる）
    var serial = 0

    /// 帯の見出し
    var title: String {
        switch kind {
        case .save: return L("保存できませんでした", "Couldn't save")
        case .note: return L("ひとことを入れられませんでした", "Couldn't add the note")
        case .move: return L("動かせませんでした", "Couldn't move")
        case .share: return L("共有できませんでした", "Couldn't share")
        case .delete: return L("削除できませんでした", "Couldn't delete")
        }
    }

    /// 「もう一度」で直せるか（送り直せば通るかもしれない失敗）。項目が変わった回は、もう一度しても同じ
    var canRetry: Bool {
        switch kind {
        case .save, .share, .delete: return true
        case .note, .move: return false
        }
    }

    /// 帯の右の小ボタンの字
    var actionTitle: String {
        canRetry ? L("もう一度", "Retry") : L("閉じる", "Close")
    }

    /// 帯の説明。電波が無くて送り直す失敗なら、押す時を言う（モックの「電波が戻ったら押してください」）
    func message(offline: Bool) -> String {
        if offline && canRetry { return Self.offlineMessage }
        return detail
    }

    static var offlineMessage: String {
        L("電波が戻ったら押してください", "Tap when you're back online")
    }

    /// 読み上げ（帯が出たときに1回。見出しと説明）
    func spoken(offline: Bool) -> String {
        title + L("。", ". ") + message(offline: offline)
    }

    /// 保存の帯を、自動の保存が通ったら消すか（2026-11-25 確かめ役の指摘: 電波が戻って送れたあとも「保存できませんでした」が残った）。
    /// 送れていない事情が消え（`problem == nil`）、送っていない変更も無いときだけ。**変更が残っている間は消さない**（黙って失わない）
    func isSettled(problemRemains: Bool, dirty: Bool) -> Bool {
        kind == .save && !problemRemains && !dirty
    }

    /// 上の札（「まだ送れていません」）の「もう一度試す」を出すか。保存の帯が出ている間は帯の1か所だけにする（同じ一手を2か所に置かない）
    static func showsTopRetry(failure: TripPlanFailure?) -> Bool {
        failure?.kind != .save
    }

    /// 帯を払って閉じるか（横か下へ、これだけ動かして離した）
    static let swipeDistance: Double = 60

    static func swipeCloses(dx: Double, dy: Double) -> Bool {
        abs(dx) >= swipeDistance || dy >= swipeDistance
    }
}

/// 帯の「もう一度」で走らせる直し。**1回だけ取り出せる**（続けて2回押しても、送るのは1回・2026-11-25 確かめ役の指摘）
final class TripPlanRetry {
    private var action: (() -> Void)?

    init(_ action: (() -> Void)? = nil) { self.action = action }

    /// 取り出す（2回目からは nil）
    func take() -> (() -> Void)? {
        defer { action = nil }
        return action
    }

    var isEmpty: Bool { action == nil }
}
