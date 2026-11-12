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

    @Published private(set) var current: Message?
    /// いまの知らせに添えた「取り消す」（無ければ nil）。知らせが替わる・消えると一緒に消える
    @Published private(set) var undo: Undo?

    private var hideTask: Task<Void, Never>?

    func show(_ text: String, kind: Message.Kind = .success) {
        show(text, kind: kind, undo: nil)
    }

    /// 「取り消す」を添えて出す（約6秒）。押すと `run` を1回だけ流して知らせを消す
    func show(_ text: String, kind: Message.Kind = .success, undo: Undo?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 空の知らせは出さない（何も伝えない帯が画面を覆う）
        guard !trimmed.isEmpty else { return }
        current = Message(id: UUID(), text: trimmed, kind: kind)
        self.undo = undo
        let seconds = undo == nil ? Self.duration : Self.undoDuration
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

    /// 「取り消す」を押した。知らせを消してから戻す（続けて押しても1回だけ）。
    /// 戻せなかったら失敗の知らせで一言（2026-11-12 判断・確かめ役の指摘: 失敗が伝わらなかった）
    func performUndo() async {
        guard let undo else { return }
        dismiss()
        if !(await undo.run()) { show(undo.failure, kind: .failure) }
    }
}
