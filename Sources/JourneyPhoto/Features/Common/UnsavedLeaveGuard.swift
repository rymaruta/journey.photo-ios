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
            // 🔴 **シートの中に積まれた画面では、下へ払うとシートごと閉じる。** 戻るを
            // 隠しても止まるのは左端から払う戻るだけで、旅行プラン（メニューのシート）・
            // 親しい友達（投稿のシート）は払うだけで下書きが確かめもなく消えていた。
            // シートの外では何もしない
            .interactiveDismissDisabled(leave != .now)
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

/// 送っていない変更があるシートの「✕」と下へ払う閉じ方（`UnsavedLeave`）。
///
/// 上の `unsavedLeaveGuard` は**積み重ねた画面の戻る**の形（標準の戻るを隠して
/// 自前の戻るに差し替える）で、シートの ✕ には合わない。シートでは戻るを
/// 差し替えるのではなく、**下へ払って閉じるのを止め**（`interactiveDismissDisabled`）、
/// ✕ は呼び手が `.confirm` のときに `isPresented` を立てる。
/// 判断（`UnsavedLeave`）と「保存／捨てる（破壊的）／キャンセル」の並びは同じもの
/// ——**2つ目の仕組みは作らない**。
///
/// - `saveTitle`・`discardTitle`: 画面の言葉に合わせる（ストーリーは「下書きに保存」「捨てる」）
/// - `onSave`: 保存し、**成功したときだけ閉じる**のは呼び手の仕事（失敗なら開いたまま断りを出す）
/// - 送っている最中（`.wait`）も払って閉じさせない。✕ を押せなくするのは呼び手
extension View {
    func unsavedCloseGuard(_ leave: UnsavedLeave,
                           isPresented: Binding<Bool>,
                           title: String,
                           canSave: Bool = true,
                           saveTitle: String,
                           discardTitle: String,
                           message: String,
                           onSave: @escaping () -> Void,
                           onDiscard: @escaping () -> Void) -> some View {
        self
            // 下へ払っても**跳ね返るだけ**で確認は出ない（SwiftUI には払われたことを知る口が
            // 無い）。失うものは無く、✕ から確かめられる
            .interactiveDismissDisabled(leave != .now)
            .confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
                if canSave {
                    Button(saveTitle, action: onSave)
                }
                Button(discardTitle, role: .destructive, action: onDiscard)
                Button(L("キャンセル", "Cancel"), role: .cancel) {}
            } message: {
                Text(message)
            }
    }
}
