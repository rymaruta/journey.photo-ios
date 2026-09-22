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

    var body: some View {
        Form {
            Section {
                Text(L("アカウントを削除すると、次のものが消えます。", "Deleting your account removes:"))
                VStack(alignment: .leading, spacing: 6) {
                    Label(L("投稿した写真と画像ファイル", "Your photos and image files"), systemImage: "photo")
                    Label(L("プロフィール（名前・自己紹介・アイコン）", "Your profile (name, bio, avatar)"), systemImage: "person.crop.circle")
                    Label(L("フォロー・いいね・お知らせ", "Follows, likes and activity"), systemImage: "heart")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            } footer: {
                // 嘘をつかない。実装がそうなっている（コメントは読むときに
                // 名前を伏せる扱いで、行そのものは残る）
                Text(L("他の人の写真に書いたコメントの本文は残りますが、名前は「退会したユーザー」に変わります。", "Comments you left on other photos remain, but your name becomes “Deleted user”."))
            }
            .listRowBackground(Color.clear)

            Section {
                // **`**` を書かない。** Markdown として太字になるのは
                // `Text` に**文字列リテラル**を渡したときだけで、`L(…)` の
                // 戻り値（ただの String）では記号がそのまま見える。
                // 太字にしたいなら font で言う
                Text(L("この操作は取り消せません。", "This cannot be undone."))
                    .font(.body.weight(.semibold))
                TextField(L("確認のため「\(Self.confirmWord)」と入力", "Type “\(Self.confirmWord)” to confirm"), text: $typed)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .listRowBackground(Color.clear)

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red).font(.callout) }
            }

            Section {
                Button(role: .destructive) {
                    Task { await deleteAccount() }
                } label: {
                    if isWorking {
                        HStack { ProgressView(); Text(L("削除しています…", "Deleting…")) }
                    } else {
                        Text(L("アカウントを削除する", "Delete my account"))
                    }
                }
                // **大小を区別しない。** 英語側は `DELETE` だが、入力欄は
                // 自動大文字化を切ってあるので `delete` と打つ人が出る
                // ——灰色のまま理由も出ない画面にしない
                .disabled(isWorking || !ConfirmWord.matches(typed, word: Self.confirmWord))
            }
            .listRowBackground(Color.clear)
        }
        .webScreen()
        .navigationTitle(L("アカウントの削除", "Delete account"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func deleteAccount() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            // **宛先は消す前に外す。** アカウントが消えたあとでは認証が
            // 通らず、`devices#<uid>` の行だけが残る
            await push.signingOut()
            try await environment.account.deleteAccount()
            // **消えたあとのトークンは残さない。** API Gateway の JWT 検証は
            // 署名と exp しか見ないので、残ったトークンは期限まで通る
            // （`api-user/src/types.ts` の墓石の話）
            await auth.signOut()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("削除できませんでした", "Couldn't delete")
        }
    }
}
