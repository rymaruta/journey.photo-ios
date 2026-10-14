import StoreKit
import SwiftUI

/// 退会。
///
/// **審査要件（5.1.1(v)）。** アカウントを作れるアプリは、アプリの中から
/// 削除できなければならない。**設定の中に置き、Web へ飛ばさない。**
struct DeleteAccountView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var push: PushCenter
    /// App Store 側の定期購入（設定の Pro の行と同じ読み方・`refreshSubscription`）
    @EnvironmentObject private var store: StoreService
    @Environment(\.dismiss) private var dismiss

    /// 自分のプロフィール（設定が読んだもの）。読めていなければ nil＝Pro かどうか分からない
    /// ——そのときも定期購入の知らせは出す（`ProStatusText.showsDeleteAccountSubscriptionNotice`）
    var profile: UserProfile? = nil
    /// App Store の定期購入の管理（設定の Pro の行と同じ OS のシート）
    @State private var showManage = false

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
                // 板 46 の赤い枠の札（赤 8% の地・30% の縁）。赤はテーマの危険の色
                .background(WebTheme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(WebTheme.danger.opacity(0.3), lineWidth: 1))
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            // 2026-10-11 判断: App Store の定期購入は退会しても止まらない（アプリからは解約できない）。
            // 黙っていると、退会した人に請求が続く。サーバーも App Store も「入っていない」ときだけ出さない
            if ProStatusText.showsDeleteAccountSubscriptionNotice(isPro: profile?.isPro, appStore: store.subscription) {
                Section { subscriptionNotice }
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

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
        // 設定の Pro の行（`ProSettingsSection`）と同じ OS の管理シート。写しの画面は作らない
        .manageSubscriptionsSheet(isPresented: $showManage)
        // App Store 側の定期購入を読む（`ProSettingsSection` と同じ2つ。StoreKit の問い合わせを別に作らない）
        .task {
            await store.loadProducts()
            await store.refreshSubscription()
        }
        .navigationTitle(L("アカウントの削除", "Delete account"))
        .navigationBarTitleDisplayMode(.inline)
        // 消している最中は戻らせない（戻って開き直すと、2本目の退会が走る。`ProfileEditView` と同じ）
        .navigationBarBackButtonHidden(isWorking)
        .interactiveDismissDisabled(isWorking)
    }

    private var canDelete: Bool {
        // **大小を区別しない。** 英語側は `DELETE` だが、入力欄は
        // 自動大文字化を切ってあるので `delete` と打つ人が出る
        // ——灰色のまま理由も出ない画面にしない
        !isWorking && ConfirmWord.matches(typed, word: Self.confirmWord)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            // 🔴 **門は押したその場で閉じる。** `isWorking` を Task の中で立てていたので、
            // 描き直しの前に2回押すと2本走り、退会の要求が2回飛んでいた
            // （`SettingsView.pushBinding` の「門は同期で閉じる」と同じ）
            guard canDelete else { return }
            isWorking = true
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

    /// 定期購入は止まらない、の知らせ（2026-10-11）。
    ///
    /// **赤にしない。** 板（デザインシステム「黒塗りの真鍮」）は「警告＝白＋アイコン」。赤は消えるもの・
    /// 取り消せないこと（上の札）に取っておく。地は札（`JPCard`・v2 の #0E0E0F）、ボタンは2番手の枠線
    /// （主ボタンは下の「アカウントを削除する」）
    private var subscriptionNotice: some View {
        JPCard {
            VStack(alignment: .leading, spacing: 14) {
                Label {
                    Text(L("Journey Photo Pro の定期購入は、退会しても止まりません。App Store で解約してください。",
                           "Your Journey Photo Pro subscription doesn't stop when you delete your account. Cancel it in the App Store."))
                        .font(.subheadline)
                        .foregroundStyle(WebTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(WebTheme.foreground)
                }
                Button {
                    showManage = true
                } label: {
                    Text(L("定期購入を管理", "Manage subscription"))
                        .jpPillButton(.outline)
                }
                .buttonStyle(.plain)
                .accessibilityHint(L("App Store で定期購入を管理します", "Manage your subscription in the App Store"))
                .accessibilityIdentifier("deleteAccount.manageSubscription")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("deleteAccount.subscriptionNotice")
    }

    /// 消えるものの1行（板の赤い ×）
    private func removed(_ text: String) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(WebTheme.danger)
        }
    }

    /// 呼ぶ前に `isWorking` を立てておくこと（ボタンが同期で立てる）
    private func deleteAccount() async {
        errorMessage = nil
        defer { isWorking = false }
        // **消す前に控える。** 消したあとは誰だったか分からない
        // （端末の控えを消すのに要る）
        let userId = auth.userId
        let username = try? await AuthGateway.currentUsername()
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
            // 退会した人の「受け取る」も下ろす（Cognito の削除だけ落ちて起動し直しても預け直さない）
            await push.signingOut(accountDeleted: true)
        }
        do {
            // 🔴 **Cognito の利用者も消す。** サーバーは消さないので、これが無いと
            // 退会したのに同じメールとパスワードでログインできた（審査 5.1.1(v)）
            // 🔴 **端末に残った本人の控えも消す**（`AccountLocalData`）。
            // Cognito まで消せた回だけ——途中で落ちたらアカウントは残っている。
            // 退会の途中で止まったアカウント（410）の後始末と同じ口（`completeAccountDeletion`）
            try await auth.completeAccountDeletion(userId: userId, username: username)
            // 編集した写真の控え（端末に書かない・`PhotoEditLedger`）も捨てる。
            // ログアウトでも捨てるが、退会はそれを待たずに
            environment.gallery.edits.clear()
            dismiss()
        } catch {
            errorMessage = L("写真とプロフィールは削除されました。アカウント自体の削除だけが残っています。もう一度「アカウントを削除する」を押してください",
                             "Your photos and profile were deleted, but the account itself wasn't. Tap “Delete my account” again.")
        }
    }
}
