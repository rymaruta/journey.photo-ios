import Foundation

/// 旅行プランの日程の**自動保存**（2026-11-10 判断・札 #521・板 TripPlanDays の F34「変更は自動で保存されます」）。
///
/// 右上の「保存」を外し、**手を止めてから少し待ってまとめて送る**（`delay`）。書き込みの回数を抑えるため、
/// 打つたび・運ぶたびには送らない（自動保存で書き込みが増えるのは owner が任せた・札 #521 の秘書室の決め）。
///
/// - 送るのは今と同じ口（`TripPlanService.update`・変えた項目だけ）。プランの形もサーバーも変えない
/// - **送る前に読み直し、別の端末で変わっていたら知らせて止める**（`conflicted`）。日程は丸ごと送るので、
///   黙って送ると別の端末の直しを消す
/// - **圏外・断られたときは、送れなかった直しを画面に残す**（「まだ送れていません」と「もう一度試す」）。
///   端末に控えは持たない（今の決まりのまま）ので、戻るときは今の「保存せずに戻る」の確かめを出す
/// - 送れる状態で戻るときは、確かめずに送ってから戻る（`Leave.sendThenLeave`）
enum TripAutosave {

    /// 手を止めてから送るまで（2秒・提案の「止まってから 2 秒」）
    static let delayNanoseconds: UInt64 = 2_000_000_000

    enum Problem: Equatable {
        /// 圏外で送れなかった
        case offline
        /// 送ったが断られた（サーバーの言い分）
        case failed(String)
        /// 別の端末でプランが変わっていた（送らずに止めた）
        case conflict
    }

    /// 送ってよいか。変えていて、送っている最中でなく、止めている事情（別の端末の変更）が無いとき
    static func shouldSend(dirty: Bool, busy: Bool, problem: Problem?) -> Bool {
        dirty && !busy && problem != .conflict
    }

    /// 送る前の読み直しで、別の端末の変更を見つけたか。**開いたとき（最後に合わせたとき）の版**と比べる。
    /// サーバーで消されていた（`server == nil`）ときも止める
    static func conflicted(base: TripPlan?, server: TripPlan?) -> Bool {
        guard let base else { return false }
        guard let server else { return true }
        return (base.updatedAt ?? "") != (server.updatedAt ?? "")
    }

    enum Leave: Equatable {
        /// そのまま戻る（変えていない）
        case now
        /// 送っている最中（戻らせない・途中の失敗が消えた画面に出る）
        case wait
        /// 送れる（確かめずに送ってから戻る）
        case sendThenLeave
        /// 送れていない（圏外・断られた・別の端末の変更）。今の「保存せずに戻る」の確かめを出す
        case confirm
    }

    static func leave(dirty: Bool, sending: Bool, problem: Problem?, offline: Bool) -> Leave {
        if sending { return .wait }
        guard dirty else { return .now }
        if offline || problem != nil { return .confirm }
        return .sendThenLeave
    }

    /// `UnsavedLeave`（戻るの見た目・確かめ）に読み替える。送ってから戻る回も自前の戻るを出す
    static func unsaved(_ leave: Leave) -> UnsavedLeave {
        switch leave {
        case .now: return .now
        case .wait: return .wait
        case .sendThenLeave, .confirm: return .confirm
        }
    }

    /// 画面の上に残す1行。無ければ nil
    static func banner(_ problem: Problem?, dirty: Bool) -> String? {
        switch problem {
        case .none: return nil
        case .offline?:
            return dirty ? L("圏外のため、まだ送れていません。電波が戻ったら「もう一度試す」を押してください",
                             "You're offline, so changes aren't sent yet. Tap Try again when you're back online.") : nil
        case .failed(let message)?:
            return dirty ? L("まだ送れていません。\(message)", "Not sent yet. \(message)") : nil
        case .conflict?:
            return L("別の端末でこのプランが変わりました。読み直すと、この画面で変えた分は残りません",
                     "This trip changed on another device. Reloading drops the changes made here.")
        }
    }

    /// 見出しの下の一言（板 TripPlanDays: 「変更は自動で保存されます」）
    static func status(sending: Bool, problem: Problem?) -> String {
        if sending { return L("保存しています…", "Saving…") }
        if problem != nil { return L("まだ送れていない変更があります", "Some changes aren't sent yet") }
        return L("変更は自動で保存されます", "Changes are saved automatically")
    }
}
