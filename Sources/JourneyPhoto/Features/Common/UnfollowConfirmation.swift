import SwiftUI

/// フォローを外す前の確認。
///
/// **外すときだけ聞く。** 「フォロー中」のボタンは見た目が押せる札なので、
/// 指が触れただけで外れていた（owner の「確認がほしい」）。フォローする側は
/// 押し直せば戻るうえ、確認を挟むと手数が増えるだけなので聞かない。
///
/// フォローの札はホーム・写真の詳細・人のプロフィールの3か所にあるので、
/// 文言が割れないようにここへ寄せる。
extension View {
    func unfollowConfirmation(isPresented: Binding<Bool>,
                              onConfirm: @escaping () -> Void) -> some View {
        confirmationDialog(L("フォローを外しますか？", "Unfollow?"),
                           isPresented: isPresented, titleVisibility: .visible) {
            Button(L("フォローを外す", "Unfollow"), role: .destructive, action: onConfirm)
            Button(Labels.Common.cancel, role: .cancel) { }
        }
    }
}
