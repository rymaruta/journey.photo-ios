import SwiftUI

/// 人をブロックする前の確認（2026-10-11）。
///
/// 「この人をブロック」はホームのカード・写真の詳細・人のページ・ストーリーの4か所にある。
/// 写真の詳細だけ確認が無く、メニューの押し間違い1回でブロックされていた。
/// 文言と形が割れないように、ここへ寄せる（`unfollowConfirmation` と同じ考え方）。
///
/// 2026-10-11 判断: 形は **alert**（人のページ・ストーリーと同じ）。ホームのカードは
/// `confirmationDialog` で文言も短かった（「設定からいつでも解除できます」が無い）ので、こちらに揃えた。
/// 解除できると書くのは、ブロックの重さを怖がらせすぎないため
extension View {
    func blockConfirmation(isPresented: Binding<Bool>,
                           onConfirm: @escaping () -> Void) -> some View {
        alert(BlockConfirmationText.title, isPresented: isPresented) {
            Button(BlockConfirmationText.confirm, role: .destructive, action: onConfirm)
            Button(Labels.Common.cancel, role: .cancel) {}
        } message: {
            Text(BlockConfirmationText.message)
        }
    }
}

/// 確認の文言（テストで見張る）
enum BlockConfirmationText {
    static var title: String { L("この人をブロックしますか？", "Block this person?") }
    static var confirm: String { L("ブロック", "Block") }
    static var message: String {
        L("おたがいの投稿・ストーリー・通知が見えなくなります。設定からいつでも解除できます。",
          "You won't see each other's posts, stories or notifications. You can undo this in Settings.")
    }
}
