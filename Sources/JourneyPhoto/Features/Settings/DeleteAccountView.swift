import StoreKit
import SwiftUI

/// 退会。
///
/// **審査要件（5.1.1(v)）。** アカウントを作れるアプリは、アプリの中から
/// 削除できなければならない。**設定の中に置き、Web へ飛ばさない。**
///
/// **v2（2026-10-14・板 DeleteAccount）**: 左寄せの明朝 30 の大見出し。警告の札は赤 8% の地・30% の縁・角 16
/// （`WebTheme.danger`・CLAUDE.md）で、頭に三角の印と赤の見出し、消えるものは赤の点の箇条、
/// 「この操作は取り消せません。」は札の中の白の太字。確定は危険の塗り（`JPPillStyle.danger`）で、
/// 「削除」と入れるまで押せず、その理由を下に1行（`DeleteAccountText.enableHint`）
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
    /// Apple でサインインの取り消しの結果（Apple の人だけ・`AppleSignInRevoke`）
    @State private var appleRevoke: AppleSignInRevoke.Outcome?

    var body: some View {
        Form {
            Section {
                Text(L("アカウントの削除", "Delete account"))
                    .font(JPFont.display(SettingsLayout.titleSize, relativeTo: .largeTitle))
                    .foregroundStyle(WebTheme.text)
                    .accessibilityAddTraits(.isHeader)
            }
            .jpFormRow()

            // 板: 赤い枠の札に、消えるものと残るもの
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    // 板 v2: 三角の印と赤の見出し（危険の色・#F0565A は黒地の札の上で 6:1 を超える）
                    Label {
                        Text(L("アカウントを削除すると、次のものが消えます。", "Deleting your account removes:"))
                            .font(JPFont.bodyEmphasis)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(WebTheme.danger)
                    removed(L("投稿した写真と画像ファイル", "Your photos and image files"))
                    removed(L("プロフィール（名前・自己紹介・アイコン）", "Your profile (name, bio, avatar)"))
                    removed(L("フォロー・いいね・お知らせ", "Follows, likes and activity"))
                    // 嘘をつかない。実装がそうなっている（コメントは読むときに
                    // 名前を伏せる扱いで、行そのものは残る）
                    Text(L("他の人の写真に書いたコメントの本文は残りますが、名前は「退会したユーザー」に変わります。", "Comments you left on other photos remain, but your name becomes “Deleted user”."))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    // **`**` を書かない。** Markdown として太字になるのは
                    // `Text` に**文字列リテラル**を渡したときだけで、`L(…)` の
                    // 戻り値（ただの String）では記号がそのまま見える。
                    // 太字にしたいなら font で言う。板 v2: 札の中の白の太字
                    Text(L("この操作は取り消せません。", "This cannot be undone."))
                        .font(JPFont.bodyEmphasis)
                        .foregroundStyle(WebTheme.text)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                // 板の赤い枠の札（赤 8% の地・30% の縁・角 16）。赤はテーマの危険の色（CLAUDE.md）
                .background(WebTheme.danger.opacity(DeleteAccountText.warningFillOpacity),
                            in: RoundedRectangle(cornerRadius: JPRadius.l))
                .overlay(RoundedRectangle(cornerRadius: JPRadius.l)
                    .strokeBorder(WebTheme.danger.opacity(DeleteAccountText.warningBorderOpacity), lineWidth: JPStroke.hairline))
                .accessibilityElement(children: .combine)
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
        .safeAreaInset(edge: .bottom) { deleteBar }
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
        // 画面を閉じたら 410 の知らせを受け直す（残ったアカウントはアラートが拾う）
        .onDisappear { auth.setDeletingFromScreen(false) }
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
            // 閉じるまで 410 の知らせを受けない（`AuthStore.isDeletingFromScreen`。押したその場で立てる）
            auth.setDeletingFromScreen(true)
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
    }

    /// 下に固定した帯: 確定のボタンと、まだ押せない理由の1行（板 v2・注記 12・text-3）
    private var deleteBar: some View {
        VStack(spacing: JPSpace.xs) {
            deleteButton
            if let enableHint {
                Text(enableHint)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .jpBottomBar()
    }

    /// 確定がまだ押せない理由。灰色のまま理由も出ない画面にしない（消している最中は出さない）
    private var enableHint: String? {
        canDelete || isWorking ? nil : DeleteAccountText.enableHint(word: Self.confirmWord)
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

    /// 消えるものの1行（板 v2: 赤の 5pt の点の箇条。v1 は赤い ×）
    private func removed(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(WebTheme.danger)
                .frame(width: DeleteAccountText.bulletSide, height: DeleteAccountText.bulletSide)
                // 1行目の字の中ほど（板: 上 8）
                .padding(.top, 8)
                .accessibilityHidden(true)
            Text(text)
                .font(JPFont.body)
                .foregroundStyle(WebTheme.text)
                .fixedSize(horizontal: false, vertical: true)
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
            // 🔴 **Apple でサインインの人は、先に Apple の許可を取り消す**（審査 5.1.1(v)・2026-10-21）。
            // 退会のあとでは認証が通らず、サーバーの取り消しの口を呼べない。**落ちても退会は続ける**
            // （`AppleSignInRevoke` の判断）——済ませられなかったら、退会のあとに設定から外す道を言う
            // 前の回（サーバーの退会だけ落ちた）に取り消し済みなら、シートを出し直さない
            let account = environment.account
            if appleRevoke != .revoked {
                appleRevoke = await AppleSignInRevoke.beforeDeletion(
                    idToken: await AppleSignInRevoke.freshIdToken(),
                    authorize: { try await AppleIDAuthorizer.authorizationCode() },
                    revoke: { try await account.revokeAppleSignIn(authorizationCode: $0) }
                )
            }
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
            // Apple の取り消しを済ませられなかった回は、ログインの画面に「設定から外せます」を残す
            // （退会の後半が前の文を消すので、そのあとに置く）
            if appleRevoke == .skipped { auth.errorMessage = AppleSignInText.revokeSkipped }
            dismiss()
        } catch {
            errorMessage = L("写真とプロフィールは削除されました。アカウント自体の削除だけが残っています。もう一度「アカウントを削除する」を押してください",
                             "Your photos and profile were deleted, but the account itself wasn't. Tap “Delete my account” again.")
        }
    }
}

/// 退会の画面の決まりと文言（v2 の板 DeleteAccount・2026-10-14）。テストで見張る
enum DeleteAccountText {
    /// 警告の札（CLAUDE.md・板どおり: 赤 8% の地・30% の縁）
    static let warningFillOpacity = 0.08
    static let warningBorderOpacity = 0.3
    /// 消えるものの点（板: 5pt）
    static let bulletSide: CGFloat = 5

    /// 確定がまだ押せない理由（板 v2:「「削除」と入れると押せます」）。灰色のまま理由も出ない画面にしない
    static func enableHint(word: String) -> String {
        L("「\(word)」と入れると押せます", "Type “\(word)” to enable this button")
    }
}

