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
/// - 自前の戻るは**標準の戻ると同じガラスの丸い矢印**（‹ だけ・読み上げは「戻る」）。
///   2026-11-14 判断（人間工学の点検「追加の点検 2」）: 前は `backTitle` で「‹ 旅行プラン」「‹ マイページ」と
///   前の画面の題を添えていて、変更がある間だけ戻るの形が名前つきに替わった（iOS 26 の標準の戻るは題の無い
///   ガラスの丸）。形が替わっても意味（変更がある）は伝わらず、板のデザインシステム 03「戻る、閉じるは 3 型だけ」
///   に外れる。変更があることは画面の文（旅行プランは題の下の一行）で言う。題を渡す口ごと外した
///
/// `ViewModifier` にしないのは `Shims/` の模型が持っていないため
/// （`WebTheme.webScreen`・`unfollowConfirmation` と同じ形）。
extension View {
    func unsavedLeaveGuard(_ leave: UnsavedLeave,
                           isPresented: Binding<Bool>,
                           canSave: Bool,
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
                            // 印だけ（題を添えない）。上のバーの中なので、iOS 26 は系統が標準の戻ると同じガラスの丸にする
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                                .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                                .contentShape(Rectangle())
                        }
                        // 送っている最中は戻らせない（途中の失敗が消えた画面に出る）
                        .disabled(leave == .wait)
                        .accessibilityLabel(L("戻る", "Back"))
                        .accessibilityIdentifier("unsavedLeave.back")
                    }
                }
            }
            .confirmationDialog(L("変更を保存しますか？", "Save your changes?"),
                                isPresented: isPresented, titleVisibility: .visible) {
                if canSave {
                    Button(L("保存して戻る", "Save and go back"), action: onSave)
                }
                Button(L("保存せずに戻る", "Go back without saving"), role: .destructive, action: onDiscard)
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
/// - `saveTitle`・`discardTitle`: 画面の言葉に合わせる（ストーリーは「下書きに保存」「保存せずに閉じる」）
/// - `onSave`: 保存し、**成功したときだけ閉じる**のは呼び手の仕事（失敗なら開いたまま断りを出す）
/// - 送っている最中（`.wait`）も払って閉じさせない。✕ を押せなくするのは呼び手
extension View {
    /// - `secondaryTitle`・`onSecondary`: 保存の次に置く2つ目の手（2026-10-29・#400 の下書き:
    ///   下書きから開いた回の「別の下書きとして保存」・いっぱいのときの「下書きを整理する」）。nil なら出さない
    func unsavedCloseGuard(_ leave: UnsavedLeave,
                           isPresented: Binding<Bool>,
                           title: String,
                           canSave: Bool = true,
                           saveTitle: String,
                           secondaryTitle: String? = nil,
                           discardTitle: String,
                           message: String,
                           onSave: @escaping () -> Void,
                           onSecondary: (() -> Void)? = nil,
                           onDiscard: @escaping () -> Void) -> some View {
        self
            // 下へ払っても**跳ね返るだけ**で確認は出ない（SwiftUI には払われたことを知る口が
            // 無い）。失うものは無く、✕ から確かめられる
            .interactiveDismissDisabled(leave != .now)
            .confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
                if canSave {
                    Button(saveTitle, action: onSave)
                }
                if let secondaryTitle, let onSecondary {
                    Button(secondaryTitle, action: onSecondary)
                }
                Button(discardTitle, role: .destructive, action: onDiscard)
                Button(L("キャンセル", "Cancel"), role: .cancel) {}
            } message: {
                Text(message)
            }
    }
}
