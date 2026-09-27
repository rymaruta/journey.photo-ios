import SwiftUI

/// 送っていない変更があるときの「戻る」（`UnsavedLeave`）。
///
/// 変更がある間・送っている間は**標準の戻るを隠し**（左端から払って戻るのも
/// 止まる）、自前の戻るで「保存して戻る／変更を捨てる／キャンセル」を確かめる。
/// 送っている最中の戻るは押せない。
///
/// 親しい友達（`CloseFriendsView`）で作ったものを、旅行プランの日程
/// （`TripPlanDetailView`）でも使うためにここへ寄せた——**文言と作法を割らない**。
///
/// - `canSave`: 偽なら「保存して戻る」を出さない（上限超えなど、保存できない間）
/// - `onSave`: 保存し、**成功したら画面を閉じる**のは呼び手の仕事
/// - `backTitle`: 自前の戻るに添える文字（前の画面の題）。標準の戻る「‹ 題」と
///   同じ見た目を保つ画面が渡す。nil なら ‹ だけ（親しい友達はこれまでどおり）
///
/// `ViewModifier` にしないのは `Shims/` の模型が持っていないため
/// （`WebTheme.webScreen`・`unfollowConfirmation` と同じ形）。
extension View {
    func unsavedLeaveGuard(_ leave: UnsavedLeave,
                           isPresented: Binding<Bool>,
                           canSave: Bool,
                           backTitle: String? = nil,
                           message: String,
                           onSave: @escaping () -> Void,
                           onDiscard: @escaping () -> Void) -> some View {
        self
            .navigationBarBackButtonHidden(leave != .now)
            .toolbar {
                if leave != .now {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            if leave == .confirm { isPresented.wrappedValue = true }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.body.weight(.semibold))
                                if let backTitle { Text(backTitle) }
                            }
                            .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                            .contentShape(Rectangle())
                        }
                        // 送っている最中は戻らせない（途中の失敗が消えた画面に出る）
                        .disabled(leave == .wait)
                        .accessibilityLabel(L("戻る", "Back"))
                    }
                }
            }
            .confirmationDialog(L("変更を保存しますか？", "Save your changes?"),
                                isPresented: isPresented, titleVisibility: .visible) {
                if canSave {
                    Button(L("保存して戻る", "Save and go back"), action: onSave)
                }
                Button(L("変更を捨てる", "Discard changes"), role: .destructive, action: onDiscard)
                Button(L("キャンセル", "Cancel"), role: .cancel) {}
            } message: {
                Text(message)
            }
    }
}
