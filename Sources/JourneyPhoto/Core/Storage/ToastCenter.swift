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

        static func == (lhs: Message, rhs: Message) -> Bool {
            lhs.id == rhs.id && lhs.text == rhs.text && lhs.kind == rhs.kind && lhs.actionTitle == rhs.actionTitle
        }

        /// `info`: 成功でも失敗でもない案内（届く時期など・2026-10-09）
        enum Kind { case success, failure, info }
    }

    /// 出している時間。Web と同じ 3 秒
    static let duration: TimeInterval = 3
    /// 押せる一手の付いた知らせの時間（読んで押すまでの間を取る・1.1.83）
    static let actionDuration: TimeInterval = 6

    @Published private(set) var current: Message?

    private var hideTask: Task<Void, Never>?

    func show(_ text: String, kind: Message.Kind = .success, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 空の知らせは出さない（何も伝えない帯が画面を覆う）
        guard !trimmed.isEmpty else { return }
        current = Message(id: UUID(), text: trimmed, kind: kind,
                          actionTitle: action == nil ? nil : actionTitle, action: actionTitle == nil ? nil : action)
        let duration = current?.action == nil ? Self.duration : Self.actionDuration
        // **前の消し時計を止める。** 止めないと、2つ目を出した直後に
        // 1つ目の時計が来て**すぐ消える**
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }

    func dismiss() {
        hideTask?.cancel()
        current = nil
    }
}
