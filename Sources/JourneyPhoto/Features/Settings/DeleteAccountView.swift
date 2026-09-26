import SwiftUI

/// 退会。
///
/// **審査要件（5.1.1(v)）。** アカウントを作れるアプリは、アプリの中から
/// 削除できなければならない。**設定の中に置き、Web へ飛ばさない。**
struct DeleteAccountView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var push: PushCenter
    @Environment(\.dismiss) private var dismiss

    /// 押し間違いで消えないように、決まった語を打たせる（`ConfirmWord`）。
    private static var confirmWord: String { ConfirmWord.delete }

    @State private var typed = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    /// サーバーのデータは消えたが、Cognito の利用者がまだ残っているか。
    /// 押し直したときは Cognito だけをやり直す（データの削除は済んでいる）
    @State private var dataDeleted = false

    var body: some View {
        Form {
            // 板 46: 赤い枠の札に、消えるものと残るもの
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L("アカウントを削除すると、次のものが消えます。", "Deleting your account removes:"))
                        .font(.subheadline.weight(.semibold))
                    VStack(alignment: .leading, spacing: 10) {
                        removed(L("投稿した写真と画像ファイル", "Your photos and image files"))
                        removed(L("プロフィール（名前・自己紹介・アイコン）", "Your profile (name, bio, avatar)"))
                        removed(L("フォロー・いいね・お知らせ", "Follows, likes and activity"))
                    }
                    // 嘘をつかない。実装がそうなっている（コメントは読むときに
                    // 名前を伏せる扱いで、行そのものは残る）
                    Text(L("他の人の写真に書いたコメントの本文は残りますが、名前は「退会したユーザー」に変わります。", "Comments you left on other photos remain, but your name becomes “Deleted user”."))
                        .font(.caption)
                        .foregroundStyle(WebTheme.muted2)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WebTheme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(WebTheme.danger.opacity(0.3), lineWidth: 1))
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section {
                // **`**` を書かない。** Markdown として太字になるのは
                // `Text` に**文字列リテラル**を渡したときだけで、`L(…)` の
                // 戻り値（ただの String）では記号がそのまま見える。
                // 太字にしたいなら font で言う
                Text(L("この操作は取り消せません。", "This cannot be undone."))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WebTheme.danger)
                // 板は欄の上に見出し、欄の中は語そのものの下書き
                JPField(L("確認のため「\(Self.confirmWord)」と入力", "Type “\(Self.confirmWord)” to confirm")) {
                    TextField(Self.confirmWord, text: $typed)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .jpFormRow()

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(WebTheme.danger).font(.callout) }
                    .jpFormRow()
            }

        }
        .webScreen()
        // 板は下に固定した赤い大きいボタン（スクロールしても見える）
        .safeAreaInset(edge: .bottom) { deleteButton }
        .navigationTitle(L("アカウントの削除", "Delete account"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var canDelete: Bool {
        // **大小を区別しない。** 英語側は `DELETE` だが、入力欄は
        // 自動大文字化を切ってあるので `delete` と打つ人が出る
        // ——灰色のまま理由も出ない画面にしない
        !isWorking && ConfirmWord.matches(typed, word: Self.confirmWord)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            Task { await deleteAccount() }
        } label: {
            Group {
                if isWorking {
                    HStack { ProgressView(); Text(L("削除しています…", "Deleting…")) }
                } else {
                    Text(L("アカウントを削除する", "Delete my account"))
                }
            }
            .jpPillButton(.danger)
        }
        .buttonStyle(.plain)
        .disabled(!canDelete)
        // 消している最中は薄くしない（押せないのは同じ・進み具合を見せる）
        .opacity(canDelete || isWorking ? 1 : 0.4)
        .jpBottomBar()
    }

    /// 消えるものの1行（板の赤い ×）
    private func removed(_ text: String) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(WebTheme.danger)
        }
    }

    private func deleteAccount() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        if !dataDeleted {
            do {
                try await environment.account.deleteAccount()
                dataDeleted = true
            } catch {
                // 失敗ならアカウントは残っている。通知の宛先も外さない
                errorMessage = (error as? LocalizedError)?.errorDescription ?? L("削除できませんでした", "Couldn't delete")
                return
            }
            // 端末の宛先（サーバーは `devices#` を消し済み。ここは端末側の後片付け）
            await push.signingOut()
        }
        do {
            // 🔴 **Cognito の利用者も消す。** サーバーは消さないので、これが無いと
            // 退会したのに同じメールとパスワードでログインできた（審査 5.1.1(v)）
            try await auth.deleteCognitoUser()
            dismiss()
        } catch {
            errorMessage = L("写真とプロフィールは削除されました。アカウント自体の削除だけが残っています。もう一度「アカウントを削除する」を押してください",
                             "Your photos and profile were deleted, but the account itself wasn't. Tap “Delete my account” again.")
        }
    }
}
