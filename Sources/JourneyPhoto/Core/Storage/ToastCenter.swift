import Foundation
import Combine

/// 短い知らせ（トースト）。**Web の `useToast` と同じ役目。**
///
/// それまでは、うまくいった操作は**何も言わなかった**
/// （失敗だけ赤い字で出していた）。いいね・コメント・ブロックのように
/// 画面がほとんど変わらない操作は、**押せたのかどうかが分からない**。
///
/// **積まない。** Web は複数を縦に並べるが、iPhone の幅では読み切る前に
/// 次が来る。最後の1つだけを出して、上書きする。
@MainActor
final class ToastCenter: ObservableObject {

    struct Message: Equatable, Identifiable {
        let id: UUID
        let text: String
        let kind: Kind
        /// 押せる一手（1.1.83「カードにする」）。無ければ知らせだけ
        var actionTitle: String? = nil
        var action: (() -> Void)? = nil
        /// 2つ目の一手（札 #630: ログインしていない人の知らせの「ログイン」。1つ目は「新規登録」）。1つ目が無ければ出さない
        var secondaryTitle: String? = nil
        var secondaryAction: (() -> Void)? = nil

        static func == (lhs: Message, rhs: Message) -> Bool {
            lhs.id == rhs.id && lhs.text == rhs.text && lhs.kind == rhs.kind && lhs.actionTitle == rhs.actionTitle
                && lhs.secondaryTitle == rhs.secondaryTitle
        }

        /// `info`: 成功でも失敗でもない案内（届く時期など・2026-10-09）
        enum Kind { case success, failure, info }
    }

    /// 出している時間。Web と同じ 3 秒
    static let duration: TimeInterval = 3
    /// 「取り消す」を添えた知らせの時間（下書きの「元に戻す」と同じ約6秒・`DraftLibrary.undoSeconds`）
    static let undoDuration: TimeInterval = 6

    /// 知らせに添える「取り消す」（2026-11-12 判断・トランクの案: 押せばすぐ決まり、取り消しで戻す）。
    /// `run` は戻せたかを返す。戻せなければ `failure` の一言を失敗の知らせで出す（黙って消さない）
    struct Undo {
        let title: String
        var failure: String = L("取り消せませんでした。電波のあるところでもう一度お試しください",
                                "Couldn\u{2019}t undo. Try again where you have a signal.")
        let run: @MainActor () async -> Bool
    }
    /// 押せる一手の付いた知らせの時間（読んで押すまでの間を取る・1.1.83）
    static let actionDuration: TimeInterval = 6

    @Published private(set) var current: Message?
    /// いまの知らせに添えた「取り消す」（無ければ nil）。知らせが替わる・消えると一緒に消える
    @Published private(set) var undo: Undo?

    private var hideTask: Task<Void, Never>?

    /// 知らせで覆ってはいけない所の上端（画面全体の座標・`ToastPlacement`）。地図の札のように、画面の下に押せる物を並べた
    /// 画面が出している間だけ置く。nil ならいつもの所（タブの上）
    ///
    /// 2026-11-20（run 1604・1608 の `testMapSpotCardWishAndTapMapToClose`）: 地図の札の「行きたい」（y 779〜823）の上に、
    /// 押したあとの知らせ（下から 116 の所・2行で約 780〜840）が重なり、もう一度押すと知らせを閉じるだけで「行きたい」が戻らなかった
    @Published var keepClearAbove: CGFloat?

    /// 押せる一手（`actionTitle`・`action`）を付けて出す（1.1.83「カードにする」）。どちらも無ければ知らせだけ。
    /// 1.1.84 のまとめ: 「取り消す」（`undo`・トランク）と同じ部品に両方を残す。こちらで出すと前の「取り消す」は消える
    func show(_ text: String, kind: Message.Kind = .success, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        show(text, kind: kind, actionTitle: actionTitle, action: action, secondaryTitle: nil, secondaryAction: nil)
    }

    /// 2つの一手を付けて出す（札 #630: 「新規登録」と「ログイン」）。2つ目は1つ目と一緒のときだけ出す。
    /// 別の口にしてあるのは、上の口を後ろの閉じ括弧（trailing closure）で呼ぶ所が2つ目の一手に結び付かないため
    func show(_ text: String, kind: Message.Kind, actionTitle: String?, action: (() -> Void)?,
              secondaryTitle: String?, secondaryAction: (() -> Void)?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 空の知らせは出さない（何も伝えない帯が画面を覆う）
        guard !trimmed.isEmpty else { return }
        let hasFirst = actionTitle != nil && action != nil
        let hasSecond = hasFirst && secondaryTitle != nil && secondaryAction != nil
        current = Message(id: UUID(), text: trimmed, kind: kind,
                          actionTitle: hasFirst ? actionTitle : nil, action: hasFirst ? action : nil,
                          secondaryTitle: hasSecond ? secondaryTitle : nil, secondaryAction: hasSecond ? secondaryAction : nil)
        undo = nil
        scheduleHide(current?.action == nil ? Self.duration : Self.actionDuration)
    }

    /// 「取り消す」を添えて出す（約6秒）。押すと `run` を1回だけ流して知らせを消す
    func show(_ text: String, kind: Message.Kind = .success, undo: Undo?) {
        show(text, kind: kind, seconds: undo == nil ? Self.duration : Self.undoDuration, undo: undo)
    }

    /// 出す時間を決めて「取り消す」を添える（部品箱の「付けました　元に戻す」は 3 秒・札 #711。続けて押す画面なので短く）
    func show(_ text: String, kind: Message.Kind = .success, seconds: TimeInterval, undo: Undo?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 空の知らせは出さない（何も伝えない帯が画面を覆う）
        guard !trimmed.isEmpty else { return }
        current = Message(id: UUID(), text: trimmed, kind: kind)
        self.undo = undo
        scheduleHide(max(1, seconds))
    }

    private func scheduleHide(_ seconds: TimeInterval) {
        // **前の消し時計を止める。** 止めないと、2つ目を出した直後に
        // 1つ目の時計が来て**すぐ消える**
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.current = nil
            self?.undo = nil
        }
    }

    func dismiss() {
        hideTask?.cancel()
        current = nil
        undo = nil
    }

    /// 出ている知らせがこの字のときだけ下ろす（札 #628: 「投稿しました」の1枚を出したとき、同じ投稿の知らせだけを下ろす。
    /// 別の投稿の「送れませんでした　もう一度」などは残す）
    func dismiss(ifShowing text: String) {
        guard current?.text == text else { return }
        dismiss()
    }

    /// 「取り消す」を押した。知らせを消してから戻す（続けて押しても1回だけ）。
    /// 戻せなかったら失敗の知らせで一言（2026-11-12 判断・確かめ役の指摘: 失敗が伝わらなかった）
    func performUndo() async {
        guard let undo else { return }
        dismiss()
        if !(await undo.run()) { show(undo.failure, kind: .failure) }
    }
}

/// 知らせを出す高さ（下からの余白）。いつもはタブの上（116）。覆ってはいけない所があれば、その上端より 8 上に出す
enum ToastPlacement {
    static let base: CGFloat = 116
    static let gap: CGFloat = 8

    static func bottomPadding(containerMaxY: CGFloat, keepClearAbove: CGFloat?) -> CGFloat {
        guard let top = keepClearAbove, top.isFinite, top > 0, top < containerMaxY else { return base }
        return max(base, containerMaxY - top + gap)
    }
}
