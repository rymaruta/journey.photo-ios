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
    static let standardDelayNanoseconds: UInt64 = 2_000_000_000

    /// 待つ長さ。**UI テストの見本のときだけ**（Debug・`-JPTripPlanFixture` と `-JPTripPlanAutosaveDelay <秒>`）長くできる。
    /// 2026-11-10 run 969 で、UI テストの押す間が 2.4〜4.9 秒あり（押すたびに画面の木を読む分）、2 秒の待ちでは
    /// 「続けて直す」を作れなかった。まとめて送る仕組みは同じで、待つ長さだけを替えて数える
    static var delayNanoseconds: UInt64 {
        #if DEBUG
        let seconds = UserDefaults.standard.double(forKey: "JPTripPlanAutosaveDelay")
        if TripPlanFixture.isOn, seconds > 0 { return UInt64(seconds * 1_000_000_000) }
        #endif
        return standardDelayNanoseconds
    }

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

    /// 共有したプランで、ほかの仲間の変更に重ね直して送り直す回数の上限（読み直しで見つけた回と 409 の回を合わせて数える）
    static let maxRebases = 3

    /// 送ったあとにすること
    enum AfterSave: Equatable {
        /// 送れた
        case done
        /// 読み直して重ね直し、もう一度送る（数えた後の回数）
        case retry(rebases: Int)
        /// 止めて「まだ送れていません」を出す
        case fail
    }

    /// 送ったあとの決め方。**409（ほかの仲間が先に書いた）は読み直して送り直すが、回数を必ず数える**
    /// （2026-11-12 確かめ役の指摘: 409 の道で数えておらず、読み直しが古い姿を返し続けると上限なしに送り直した）。
    /// 409 はサーバーが共有したプランにだけ返す（本人だけのプランでは返らない）ので、手元のプランが共有と
    /// 知らない古い姿でも送り直す（読み直すと共有した姿と版が届き、版を添えて送れる）
    static func afterSave(ok: Bool, conflict: Bool, rebases: Int) -> AfterSave {
        if ok { return .done }
        if conflict, rebases < maxRebases { return .retry(rebases: rebases + 1) }
        return .fail
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

    /// 画面の外（「旅行プランに入れる」のシート）でプランが書き換わったとき、日程の画面が読み直すか。
    /// **送っていない直しが無く、送っている最中でもないときだけ**（直しがあるときに読み直すと、その直しが消える。
    /// そのときは送る前の読み直しが別の変更を見つけて止める）
    static func reloadsAfterOutsideChange(dirty: Bool, sending: Bool) -> Bool {
        !dirty && !sending
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

/// 手を止めてから待って送る（`TripAutosave.delayNanoseconds`）。**直すたびに前の待ちを取り消して待ち直す**ので、
/// 待ちより短い間で続けて直すと送るのは最後の1回だけになる。
///
/// 待ち方（`sleep`）を差し替えられる形にした（2026-11-10 札 #521）: UI テストは押す間が 2.4〜4.9 秒あり、
/// 実際の 2 秒の待ちでは「続けて直す」を作れない。単体テストで時計を差し替えて、0.5 秒おき・2.5 秒おきを数で見る
@MainActor
final class TripAutosaveDebouncer {

    typealias Sleep = @MainActor (UInt64) async throws -> Void
    typealias Action = @MainActor () async -> Void

    private let delay: UInt64
    private let sleep: Sleep
    /// 待っている仕事。**待つ間だけ**持つ（待ち終えたら外してから送る）
    private var waiting: Task<Void, Never>?
    /// 送っている最中
    private var sending = false
    /// 送っている間に直された（送り終えたら、この仕事で待ち直す）
    private var pendingAfterSend: Action?

    init(delay: UInt64 = TripAutosave.delayNanoseconds,
         sleep: @escaping Sleep = { try await Task.sleep(nanoseconds: $0) }) {
        self.delay = delay
        self.sleep = sleep
    }

    /// 待ち直す。待ち終えたら `action`（送る）。
    ///
    /// 🔴 **取り消すのは待っている間だけ**（2026-11-10 確かめ役の指摘・札 #521）。以前は送っている仕事まで
    /// 取り消していた——送る仕事の中の `flush()` が `cancel()` を呼ぶと自分を取り消し、続く読み直し
    /// （`RequestLimiter.acquire` の取り消しの確かめ）が投げて**一度も送れなかった**。送っている間に直したときは、
    /// 送っている仕事を止めず、送り終えてから待ち直す
    func schedule(_ action: @escaping Action) {
        if sending {
            pendingAfterSend = action
            return
        }
        waiting?.cancel()
        let delay = delay
        let sleep = sleep
        waiting = Task { @MainActor [weak self] in
            do { try await sleep(delay) } catch { return }
            guard let self, !Task.isCancelled else { return }
            // 待ち終えた。ここからは取り消さない（`cancel()` が届かないよう外してから送る）
            self.waiting = nil
            self.sending = true
            await action()
            self.sending = false
            if let next = self.pendingAfterSend {
                self.pendingAfterSend = nil
                self.schedule(next)
            }
        }
    }

    /// 待っている間の仕事を取り消す（すぐ送るとき・保存せずに戻るとき）。**送っている仕事は止めない**
    func cancel() {
        waiting?.cancel()
        waiting = nil
        pendingAfterSend = nil
    }
}
