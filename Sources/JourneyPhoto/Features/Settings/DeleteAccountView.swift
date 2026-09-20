import SwiftUI

/// 退会。
///
/// **審査要件（5.1.1(v)）。** アカウントを作れるアプリは、アプリの中から
/// 削除できなければならない。**設定の中に置き、Web へ飛ばさない。**
struct DeleteAccountView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    /// 押し間違いで消えないように、決まった語を打たせる。
    ///
    /// **その人の言葉で打たせる。** 日本語に固定していたので、英語の端末には
    /// 「Type “削除” to confirm」と出ていた——日本語入力を持たない人は
    /// **アプリから退会できない**（審査 5.1.1(v) を見るのはたいてい
    /// 英語の審査官）。
    private static var confirmWord: String { L("削除", "DELETE") }

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
                .disabled(isWorking || typed.trimmingCharacters(in: .whitespaces) != Self.confirmWord)
            }
        }
        .navigationTitle(L("アカウントの削除", "Delete account"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func deleteAccount() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
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
