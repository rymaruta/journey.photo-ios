import SwiftUI

/// 退会。
///
/// **審査要件（5.1.1(v)）。** アカウントを作れるアプリは、アプリの中から
/// 削除できなければならない。**設定の中に置き、Web へ飛ばさない。**
struct DeleteAccountView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    /// 押し間違いで消えないように、決まった語を打たせる
    private static let confirmWord = "削除"

    @State private var typed = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Text("アカウントを削除すると、次のものが消えます。")
                VStack(alignment: .leading, spacing: 6) {
                    Label("投稿した写真と画像ファイル", systemImage: "photo")
                    Label("プロフィール（名前・自己紹介・アイコン）", systemImage: "person.crop.circle")
                    Label("フォロー・いいね・お知らせ", systemImage: "heart")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            } footer: {
                // 嘘をつかない。実装がそうなっている（コメントは読むときに
                // 名前を伏せる扱いで、行そのものは残る）
                Text("他の人の写真に書いたコメントの本文は残りますが、名前は「退会したユーザー」に変わります。")
            }

            Section {
                Text("**この操作は取り消せません。**")
                TextField("確認のため「\(Self.confirmWord)」と入力", text: $typed)
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
                        HStack { ProgressView(); Text("削除しています…") }
                    } else {
                        Text("アカウントを削除する")
                    }
                }
                .disabled(isWorking || typed.trimmingCharacters(in: .whitespaces) != Self.confirmWord)
            }
        }
        .navigationTitle("アカウントの削除")
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
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "削除できませんでした"
        }
    }
}
