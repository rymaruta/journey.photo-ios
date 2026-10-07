import Foundation
// Linux では URLCache が別モジュールに居る（iOS では何も起きない）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
// `ObservableObject` と `@Published` は Combine のもの。SwiftUI を読む
// ファイルは再輸出で使えるが、ここは読んでいないので明示する
import Combine
import Amplify
import AWSCognitoAuthPlugin

/// ログイン状態を画面に配る。
@MainActor
final class AuthStore: ObservableObject {

    enum State: Equatable {
        case unknown
        case signedOut
        case signedIn(userId: String)
    }

    @Published private(set) var state: State = .unknown
    @Published var errorMessage: String?
    @Published private(set) var isWorking = false
    /// 管理者か（ID トークンの `cognito:groups` に admin）。**メニューの「管理」の
    /// 出し分けだけ**に使う——権限の判断はサーバーがする（`IdTokenClaims`）
    @Published private(set) var isAdmin = false
    /// 自分のプロフィールを**画面の外から**書き換えた回数（ログイン直後の表示名など）。
    /// マイページは `.task(id: userId)` で1度しか読まないので、同時に走った読み込みが
    /// 先に返ると名前の無い古い値のまま残る。これが増えたら読み直す
    @Published private(set) var profileRevision = 0

    func noteProfileChanged() { profileRevision += 1 }

    var userId: String? {
        if case .signedIn(let id) = state { return id }
        return nil
    }

    /// まだ分かっていない（起動直後の確認中）。
    ///
    /// **`userId == nil` だけで判断しない。** 確認が終わる前に
    /// 「ログインしてください」を出すと、ログイン済みの人にも一瞬それが
    /// 見える（Web 側の「確かめられなかった回に案内を出さない」と同じ話）。
    var isResolving: Bool { state == .unknown }

    /// ログアウトの扱いだが、**本当にログアウトしたかは分からない**
    /// （起動時に Amplify はログイン中と答えたのに、本人の ID が取れなかった）。
    /// 通知の宛先はこの回に触らない——触ると、圏外で起動しただけの人の端末を
    /// APNs から外してしまう
    private(set) var isSignedOutUncertain = false
    /// 直近のログアウトが**期限切れ**によるものか（本人が押したのではない）。
    /// 期限切れは同じ人がすぐ入り直すことが多いので、裏で送っていたストーリーの
    /// 残りを捨てない（`StoryUploadCenter`）——別の人が入れば `userChanged` が捨てる
    private(set) var signedOutByExpiry = false

    private var expiryObserver: NSObjectProtocol?
    private var deletionObserver: NSObjectProtocol?

    /// 退会の途中で止まったアカウント（サーバーのデータは消え、Cognito の利用者が残っている）。
    /// 立ったら画面の根が「退会の手続きが途中です」を出す（`JourneyPhotoApp`）
    @Published private(set) var deletionPending = false
    /// その残りを済ませている最中か（知らせを出し直さない・二重に走らせない）
    @Published private(set) var isFinishingDeletion = false
    /// 残りを済ませられなかった理由（もう一度押してもらう）
    @Published private(set) var deletionFailure: String?
    /// Cognito に頼む口（試験で差し替える）
    private let gateway: AuthStoreGateway
    /// 期限切れのログアウトを走らせている最中か（`expireSession`）
    private var isExpiring = false
    /// 本人が押したログアウトを走らせている最中か（`startSigningOut`）。
    ///
    /// 🔴 **2026-10-07 判断: 印は画面ではなくここに持つ。** メニュー（`SiteMenuView`）は
    /// 押すと先に閉じる作りで、画面の `@State` では2発目を止められなかった
    /// （閉じる動きの間にもう一度押せて、通知の宛先外しとログアウトが2本走る）。
    /// 設定（`SettingsView`）も同じ印を見る——どこから押しても1本だけ
    @Published private(set) var isSigningOut = false
    /// サインアウト・退会で空にする通信の控え。`APIClient`（既定の設定）と
    /// `AsyncImage` はどちらも `URLCache.shared` を使う（試験で差し替える）
    var responseCache: URLCache = .shared

    init(gateway: AuthStoreGateway = .live) {
        self.gateway = gateway
        // ログインの期限切れ（`AuthGateway.idToken`）を受けてログアウトに倒す
        expiryObserver = NotificationCenter.default.addObserver(
            forName: .authSessionExpired, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.expireSession() }
        }
        deletionObserver = NotificationCenter.default.addObserver(
            forName: .accountDeletionPending, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.noteDeletionPending() }
        }
    }

    /// 自分のプロフィールが 410 だった（`ProfileService.myProfile`）。ログイン中だけ立てる
    func noteDeletionPending() {
        guard userId != nil else { return }
        deletionPending = true
    }

    /// 「退会の手続きが途中です」の「完了する」。**門は押したその場で閉じる**
    /// （Task の中で閉じると、描き直しの前に2回押せて2本走る——`DeleteAccountView` と同じ）
    func startFinishingDeletion(deleteServerData: @escaping @MainActor () async throws -> Void,
                                releaseDevice: @escaping @MainActor () async -> Void) {
        guard deletionPending, !isFinishingDeletion else { return }
        isFinishingDeletion = true
        Task { await finishPendingDeletion(deleteServerData: deleteServerData, releaseDevice: releaseDevice) }
    }

    /// 退会の途中で止まったアカウントの残りを済ませる。
    ///
    /// 🔴 **サーバーの退会（`DELETE /user/account`）からやり直す。** 410 は墓石が書けた
    /// ことしか言わない——墓石の後の掃除（フォロー・お知らせ・いいねなど）が途中で
    /// 切れた回もある。Cognito だけ消すと、その残りを消せる人がいなくなる。サーバーは
    /// やり直しを想定している（`account.ts` の `deleteAccount`——済んだ分は飛ばし、
    /// 残りを消す）。落ちたら Cognito に進まない（もう一度押してもらう）。
    /// そのあと退会の後半（`completeAccountDeletion`）を走らせる。
    ///
    /// - Parameters:
    ///   - deleteServerData: サーバーの退会（`AccountService.deleteAccount`）
    ///   - releaseDevice: 端末の通知の宛先の後片付け（`PushCenter.signingOut(accountDeleted:)`）
    func finishPendingDeletion(deleteServerData: @MainActor () async throws -> Void,
                               releaseDevice: @MainActor () async -> Void,
                               localDefaults: UserDefaults = .standard) async {
        guard deletionPending else { isFinishingDeletion = false; return }
        isFinishingDeletion = true
        deletionFailure = nil
        defer { isFinishingDeletion = false }
        // **消す前に控える**（消したあとは誰だったか分からない）
        let id = userId
        let username = try? await gateway.currentUsername()
        do {
            try await deleteServerData()
        } catch {
            deletionFailure = L("アカウントの削除を完了できませんでした。通信できる所でもう一度お試しください",
                                "Couldn't finish deleting your account. Please try again with a connection.")
            return
        }
        await releaseDevice()
        do {
            try await completeAccountDeletion(userId: id, username: username, localDefaults: localDefaults)
            deletionPending = false
        } catch {
            deletionFailure = L("アカウントの削除を完了できませんでした。通信できる所でもう一度お試しください",
                                "Couldn't finish deleting your account. Please try again with a connection.")
        }
    }

    /// ログインの期限が切れた。**ログイン中の見た目のまま何もできない**状態を作らない
    ///
    /// 🔴 **何通来ても1回だけ走らせる。** 画面の口が一斉に 401 になると、期限切れの
    /// 知らせが同時に何通も届く。`userId` を見るだけだと、1本目がログアウトを待って
    /// いる間（まだ `.signedIn`）に2本目も通り、ログアウトが並んで走っていた。
    /// 印は**最初の await より前に**立てる（MainActor の上なので、ここまでは割り込まれない）
    func expireSession() async {
        guard userId != nil, !isExpiring else { return }
        isExpiring = true
        defer { isExpiring = false }
        await signOut(byExpiry: true)
        errorMessage = L("ログインの期限が切れました。もう一度ログインしてください。",
                         "Your session has expired. Please sign in again.")
    }

    /// 起動時に一度。**「確かめられなかった」と「ログインしていない」を
    /// 混ぜない**——圏外なだけの人をログイン画面に飛ばさないため、
    /// 判定できない回は `.unknown` のままにする。
    func restore() async {
        #if DEBUG
        // **絵を撮るためだけの、鍵を持たないログイン**（Debug のみ・owner 承認済み）。
        //
        // CI の巡回はログインしない（資格情報が無い）ので、マイページは
        // **実機の絵を1枚も撮れていなかった**——`docs/MOCK_PARITY.md` が
        // その1画面だけ ❌ にしていた理由。
        //
        // ここで入れるのは**利用者 ID だけ**で、トークンは1つも作らない:
        //
        //  - 公開の写真から「この人のぶん」を選り分ける画面（作品の格子・
        //    訪問した国・数え）は**本物のデータで描かれる**
        //  - 鍵の要る口（ハイライト・行きたい場所・投稿）は 401 になり、
        //    画面はその「取れなかった」側を出す。**嘘の中身は出ない**
        //
        // **Release には入らない**（`#if DEBUG`）。TestFlight に上げる
        // ビルドは Release なので、出荷物にこの口は無い。既存の
        // `-JPSiteBaseURL`（`AppConfig`）とまったく同じ形。
        // 渡す値は公開 API が返している `userId` そのもので、資格情報ではない。
        if let previewId = PreviewSession.userId {
            state = .signedIn(userId: previewId)
            return
        }
        #endif
        // 🔴 **前のログアウトで端末の中のログインを消せなかったなら、ログイン中に戻さない**
        // （`SignOutLatch` の「2026-10-02 判断」）。Amplify は控えが残っているので
        // 「ログイン中」と答えるが、本人はログアウトを押している。もう一度消してみて、
        // 消えても消えなくても未ログインとして始める。**消せない回が上限に達したら諦めて、
        // 印の無かった頃と同じく Amplify の答えに従う**（閉じ込めない・同じ注記）
        if gateway.latch.isSet, !gateway.latch.giveUpIfExhausted() {
            _ = await gateway.signOut()
            state = .signedOut
            isAdmin = false
            return
        }
        guard await gateway.isSignedIn() else {
            state = .signedOut
            isAdmin = false
            return
        }
        let id = try? await gateway.currentUserId()
        // **期限切れは起動時に見つける。** ログイン中の見た目のまま始めない。
        // 圏外などで判定できない回は `false`（ログイン中のまま進む）。
        // **ID が取れなかった回も見る**——見ないと、期限切れなのに「本当に
        // ログアウトしたか分からない」扱いになり、通知の宛先を外さない
        if await gateway.isSessionExpired() {
            await signOut(byExpiry: true)
            errorMessage = L("ログインの期限が切れました。もう一度ログインしてください。",
                             "Your session has expired. Please sign in again.")
            return
        }
        if let id {
            state = .signedIn(userId: id)
            await refreshAdmin()
        } else {
            isSignedOutUncertain = true
            state = .signedOut
            isAdmin = false
        }
    }

    /// ID トークンから管理者かを読み直す。**取れなければ管理を出さない**
    private func refreshAdmin() async {
        let token = try? await AuthGateway.idToken()
        isAdmin = token.map { IdTokenClaims.isAdmin(jwt: $0) } ?? false
    }

    /// 直近の失敗の種類。**文言でも綴りでもなく、型で分岐する。**
    @Published private(set) var lastFailure: AuthFailure = .none

    /// 直近の失敗が「まだ確認していないアカウント」か。
    var lastFailureWasUnconfirmed: Bool { lastFailure == .userNotConfirmed }

    /// 直近の失敗が「もう登録されているメールアドレス」か。
    var lastFailureWasExistingAccount: Bool {
        lastFailure == .usernameExists || lastFailure == .aliasExists
    }

    func signIn(email: String, password: String) async {
        // 🔴 **「本当にログアウトしたか分からない」まま入り直すときは、先に Amplify の
        // 中の古いログインを外す。** この状態では `AuthGateway.signOut()` を呼んで
        // いないので Amplify はログイン中のままで、`signIn` は「既にログイン中」
        // （invalidState）で断り、アプリを強制終了するまで誰もログインできなかった
        // **`run` の中で外す**（二度押し止め・くるくるの内側）——外に置くと、圏外で
        // 外すのを待つ間にもう一度押され、2本目の外しが1本目のログインを消しうる
        await run {
            // 前のログアウトで端末の中のログインを消せなかった回（`SignOutLatch`）も同じ
            if self.isSignedOutUncertain || self.gateway.latch.isSet {
                _ = await self.gateway.signOut()
            }
            // **invalidState を「前のログインが残っている」と読むのはログインの時だけ。**
            // ほかの操作（登録・パスワード変更など）の invalidState は別の理由なので、
            // `AuthFailure` では読み替えない（前と同じ汎用の文のまま）
            do {
                _ = try await self.gateway.signIn(email, password)
            } catch let error as AuthError {
                if case .invalidState = error { throw SignInIncomplete.leftoverSession }
                throw error
            }
            let id = try await self.gateway.currentUserId()
            self.isSignedOutUncertain = false
            self.signedOutByExpiry = false
            self.gateway.latch.clear()
            self.state = .signedIn(userId: id)
            await refreshAdmin()
        }
        // 🔴 **ログインでは「アカウントが無い」と「違います」を同じ文にする**（Web の signIn と
        // 同じ）。分けると、アカウントの有無をログイン画面で確かめられる。種類（`lastFailure`）
        // は残す——ほかの流れ（送り直し・退会）の文は変えない
        if lastFailure == .userNotFound {
            errorMessage = AuthMessage.text(for: .notAuthorized)
        }
    }

    /// 本人が押したログアウト（メニュー・設定の両方がここを通る）。
    /// **門は押したその場で閉じる**（`Task` の中で閉じると、描き直しの前に2回押せる——
    /// `startFinishingDeletion` と同じ形）。
    ///
    /// - Parameter releaseDevice: 通知の宛先を外す（`PushCenter.signingOut`）。
    ///   **ログアウトの前に呼ぶ**——あとだと認証が通らず外せない
    @discardableResult
    func startSigningOut(releaseDevice: @escaping @MainActor () async -> Void) -> Task<Void, Never>? {
        guard userId != nil, !isSigningOut else { return nil }
        isSigningOut = true
        return Task {
            defer { isSigningOut = false }
            await releaseDevice()
            await signOut()
        }
    }

    func signOut(byExpiry: Bool = false) async {
        isSignedOutUncertain = false
        signedOutByExpiry = byExpiry
        // 端末から消せなくても**画面はログアウトの扱いにする**（ここで止めると、押したのに
        // 何も起きない）。次の起動でログイン中に戻さないのは `SignOutLatch` の役目
        _ = await gateway.signOut()
        settleSignedOut()
    }

    /// サインアウトした扱いにする（サインアウトと退会の両方）。
    ///
    /// **前の画面の失敗（パスワード変更など）をログイン画面に持ち越さない。** 退会の道は
    /// これを通っていなかったので、パスワード変更で間違えたあと退会すると、ログイン画面に
    /// 「いまのパスワードが違います」が赤字で残っていた
    func settleSignedOut() {
        // 退会の途中の知らせは、その人がログインしている間だけのもの
        deletionPending = false
        deletionFailure = nil
        // 共有のために書いた旅の一冊の画像（表紙の写真を含む）を次の人に残さない
        TripBookCard.removeAll()
        // 旅の写真から引いた地名の控え（その人の旅先が分かる）も次の人に残さない
        LibraryTripModel.forgetPlaceNames()
        // **通信の控え（URLCache）も次の人に残さない**（2026-10-03）。API の応答
        // （`/user/profile`・`/user/photos` の下書きと限定写真の署名つき URL・
        // `/user/notifications` は Cache-Control を付けずに返る）と限定写真の画像が、
        // 端末の Caches に残りうる。退会の「端末の控えも消す」（`AccountLocalData`）とも
        // 食い違っていた。公開の写真も消えるが、次に開いたときに取り直すだけ
        responseCache.removeAllCachedResponses()
        state = .signedOut
        isAdmin = false
        errorMessage = nil
        lastFailure = .none
    }

    /// 退会の最後の一歩: Cognito の利用者を消す（`AuthGateway.deleteUser`）。
    /// 消せたらサインアウトの扱いにする。**失敗は投げる**——呼び手が
    /// 「データは消えたがアカウントが残っている」と言い分ける
    ///
    /// **「もう居ない」は消せた扱い。** Cognito 側で消えたのに返事だけ落ちた回は、
    /// 押し直すと手元のトークンで DeleteUser を呼び直して `userNotFound` が返る。
    /// 失敗として投げると「もう一度押して」が永久に続き、抜けられない
    func deleteCognitoUser() async throws {
        do {
            try await gateway.deleteUser()
        } catch let error as AuthError where AuthFailure(error).meansUserAlreadyGone {
            // 消えている。下のサインアウトへ進む
        }
        _ = await gateway.signOut()
        settleSignedOut()
    }

    /// 退会の後半（サーバーのデータを消した後）: Cognito の利用者を消し、端末に残った本人の
    /// 控え（`AccountLocalData`）を消す。**退会の画面と「退会の途中で止まったアカウント」
    /// （410・`finishPendingDeletion`）の両方がここを通る**——片方だけ直して食い違わないように。
    ///
    /// 控えを消すのは Cognito まで消せた回だけ（途中で落ちたらアカウントは残っている）。
    /// 失敗は投げる
    func completeAccountDeletion(userId: String?, username: String?,
                                 localDefaults: UserDefaults = .standard) async throws {
        try await deleteCognitoUser()
        if let userId {
            AccountLocalData.remove(userId: userId, username: username, defaults: localDefaults)
        }
    }

    /// - Returns: 確認コード送信に使う UUID。失敗したら nil。
    func signUp(email: String, password: String) async -> String? {
        var username: String?
        await run {
            username = try await AuthGateway.signUp(email: email, password: password)
        }
        return username
    }

    /// 確認コードを送り直す。**届かない／消したときの出口**が無いと、
    /// 登録の途中で詰んだ人はアカウントを作り直すしかなくなる。
    func resendSignUpCode(username: String) async -> Bool {
        var ok = false
        await run {
            try await AuthGateway.resendSignUpCode(username: username)
            ok = true
        }
        return ok
    }

    /// ログインしたままパスワードを変える。
    func changePassword(current: String, new: String) async -> Bool {
        var ok = false
        await run {
            try await AuthGateway.changePassword(current: current, new: new)
            ok = true
        }
        // この画面にメールアドレスの欄は無い（共通の「メールアドレスかパスワードが違います」は合わない）。
        // **期限切れも同じ種類（`.notAuthorized`）に畳まれる**ので、先に見分ける——
        // 見分けないと、正しいパスワードを何度打っても「違います」と出る
        if lastFailure == .notAuthorized {
            if await gateway.isSessionExpired() {
                await expireSession()
            } else {
                errorMessage = L("いまのパスワードが違います", "Your current password is incorrect")
            }
        }
        return ok
    }

    /// パスワードの再設定を始める（メールにコードが届く）。
    func startPasswordReset(email: String) async -> Bool {
        var ok = false
        await run {
            try await AuthGateway.resetPassword(email: email)
            ok = true
        }
        // 🔴 **無いアカウントでも「送りました」と同じに進める**（Web の forgotPassword と同じ）。
        // 断ると、再設定の画面でアカウントの有無を確かめられる
        if !ok, lastFailure == .userNotFound {
            ok = true
            lastFailure = .none
            errorMessage = nil
        }
        return ok
    }

    /// 届いたコードで新しいパスワードを決める。
    func confirmPasswordReset(email: String, code: String, newPassword: String) async -> Bool {
        var ok = false
        await run {
            try await AuthGateway.confirmResetPassword(
                email: email, newPassword: newPassword, code: code
            )
            ok = true
        }
        // 🔴 **無いアカウントは「コードが違います」と同じ文にする。** 1段目（`startPasswordReset`）で
        // 隠しても、ここで「アカウントが見つかりません」と出ると有無が分かる
        if lastFailure == .userNotFound {
            errorMessage = AuthMessage.text(for: .codeMismatch)
        }
        return ok
    }

    func confirmSignUp(username: String, code: String) async -> Bool {
        var ok = false
        await run {
            try await AuthGateway.confirmSignUp(username: username, code: code)
            ok = true
        }
        // 🔴 **「もう確認済み」は成功として扱う**（Web の `confirmSignUp` と同じ）。確認は
        // 済んだのに返事が届かなかった回（圏外・PostConfirmation の失敗）に押し直すと
        // Cognito は NotAuthorized を返し、「メールアドレスかパスワードが違います」で
        // 確認画面から出られなくなっていた
        if !ok, lastFailure.meansAlreadyConfirmed {
            ok = true
            lastFailure = .none
            errorMessage = nil
        }
        // 別のアカウントがこのメールで確認済み（同じ人が登録し直した）。次の手を言う
        if lastFailure == .aliasExists {
            errorMessage = L("このメールアドレスはすでに登録されています。そのアカウントでログインするか、パスワードを再設定してください",
                             "This email is already registered. Sign in to that account or reset its password.")
        }
        return ok
    }

    private func run(_ work: () async throws -> Void) async {
        // 🔴 **走っている間は2本目を始めない。** ボタンは `isWorking` で止めているが、
        // 立てるのは押した後の Task の中なので、同じフレームで2回押すと2本走っていた
        // （登録では未確認のアカウントが2つできうる）。2本目は何もせずに戻る
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        lastFailure = .none
        defer { isWorking = false }
        do {
            try await work()
        } catch let incomplete as SignInIncomplete {
            lastFailure = incomplete.failure
            errorMessage = AuthMessage.text(for: lastFailure)
        } catch let error as AuthError {
            // **文言だけでなく、種類も残す。** 画面は「未確認だから確認へ送る」
            // のような分岐をしたい——文言で判定すると、言い回しを直すたびに
            // 静かに壊れる
            lastFailure = AuthFailure(error)
            errorMessage = AuthMessage.text(for: lastFailure)
        } catch {
            lastFailure = .other
            errorMessage = error.localizedDescription
        }
    }
}

/// `AuthStore` が Cognito に頼む口。**試験で差し替える**——Amplify は Linux の試験では
/// 動かない（模型）ので、ログアウトの並び・結果の扱いを見るにはここを替える。
/// 本番は `AuthGateway` そのまま
struct AuthStoreGateway: Sendable {
    var isSignedIn: @Sendable () async -> Bool
    var currentUserId: @Sendable () async throws -> String
    var currentUsername: @Sendable () async throws -> String
    var isSessionExpired: @Sendable () async -> Bool
    var signOut: @Sendable () async -> SignOutOutcome
    var deleteUser: @Sendable () async throws -> Void
    /// 前のログアウトで端末の中のログインを消せなかった印（`SignOutLatch`）。
    /// 本番の `signOut`（`AuthGateway.signOut`）が同じ印を進め・外す
    var latch: SignOutLatch = SignOutLatch()
    var signIn: @Sendable (_ email: String, _ password: String) async throws -> Bool = { email, password in
        try await AuthGateway.signIn(email: email, password: password)
    }

    static let live = AuthStoreGateway(
        isSignedIn: { await AuthGateway.isSignedIn() },
        currentUserId: { try await AuthGateway.currentUserId() },
        currentUsername: { try await AuthGateway.currentUsername() },
        isSessionExpired: { await AuthGateway.isSessionExpired() },
        signOut: { await AuthGateway.signOut() },
        deleteUser: { try await AuthGateway.deleteUser() }
    )
}

/// ログインが「続きの段」で止まった（`AuthGateway.outcome`）
enum SignInIncomplete: Error, Equatable {
    case passwordResetRequired
    case unsupportedStep
    /// 端末に前のログインが残っていて、Amplify が断った（invalidState・`AuthStore.signIn`）
    case leftoverSession

    var failure: AuthFailure {
        switch self {
        case .passwordResetRequired: return .passwordResetRequired
        case .unsupportedStep: return .signInIncomplete
        case .leftoverSession: return .alreadySignedIn
        }
    }
}

/// 失敗の種類。
///
/// **`String(describing:)` の中身で判定しない。** Amplify Swift が持っている
/// のは `AWSCognitoAuthError`（**lowerCamel**——`userNotConfirmed`）で、
/// JS SDK の `UserNotConfirmedException` とは綴りが違う。Web から写した
/// 文字列で照合していたので、**どの分岐も一度も当たらない**状態だった。
enum AuthFailure: Equatable {
    case none
    case userNotConfirmed
    case usernameExists
    case aliasExists
    case invalidPassword
    case invalidParameter
    case notAuthorized
    case userNotFound
    case codeMismatch
    case codeExpired
    case limitExceeded
    case network
    /// パスワードの再設定が要る（管理者が再設定した・漏えいの疑いで止められた）
    case passwordResetRequired
    /// アプリで続けられないログインの段（新しいパスワードの設定・多要素認証など）
    case signInIncomplete
    /// 端末に前のログインが残っていて、ログインを断られた（ログインの操作での Amplify の
    /// `invalidState`・`SignInIncomplete.leftoverSession`）。**前のログインを渡さない**
    /// （`SignOutLatch` の「2026-10-02 判断」）
    case alreadySignedIn
    case other

    init(_ error: AuthError) {
        if let cognito = error.underlyingError as? AWSCognitoAuthError {
            switch cognito {
            case .userNotConfirmed: self = .userNotConfirmed
            case .usernameExists: self = .usernameExists
            case .aliasExists: self = .aliasExists
            case .invalidPassword: self = .invalidPassword
            case .invalidParameter: self = .invalidParameter
            case .userNotFound: self = .userNotFound
            case .codeMismatch: self = .codeMismatch
            case .codeExpired: self = .codeExpired
            case .limitExceeded, .requestLimitExceeded, .failedAttemptsLimitExceeded:
                self = .limitExceeded
            case .network: self = .network
            default: self = .other
            }
            return
        }
        // 種別が入っていない回もある（`AuthError` そのものの種類で見る）
        switch error {
        case .notAuthorized: self = .notAuthorized
        case .sessionExpired: self = .notAuthorized
        default: self = .other
        }
    }

    /// 確認コードを送ったときの「もう確認済み」（Cognito は NotAuthorized で返す）。
    /// 確認の押し直しでは**成功**として扱う
    var meansAlreadyConfirmed: Bool { self == .notAuthorized }

    /// 相手の利用者がもう存在しない（退会の押し直しで「消せた」とみなす）。
    var meansUserAlreadyGone: Bool { self == .userNotFound }

    /// 控えを捨ててよい失敗か（**この控えはもう使えない**ときだけ）。
    var isPermanent: Bool {
        self == .notAuthorized || self == .userNotFound || self == .invalidParameter
    }
}

/// Cognito の英文をそのまま出さない。
///
/// Web 側の反省がそのまま当てはまる: `InvalidParameterException` の
/// `message` は "Member must satisfy regular expression pattern: ..." の
/// ような英文で、**読んでも直し方が分からない**。
enum AuthMessage {

    static let passwordRule =
        L("パスワードは8文字以上で、英大文字・小文字・数字・記号（!@#$%など）をそれぞれ1文字以上含める必要があります",
          "Password must be at least 8 characters and include an uppercase letter, a lowercase letter, a number and a symbol (!@#$% etc.)")

    static func text(for failure: AuthFailure) -> String {
        switch failure {
        case .usernameExists, .aliasExists:
            return L("このメールアドレスはすでに登録されています", "This email is already registered")
        case .invalidPassword:
            return passwordRule
        case .invalidParameter:
            return L("メールアドレスの形式か、\(passwordRule)", "Check the email address, or: \(passwordRule)")
        case .notAuthorized:
            return L("メールアドレスかパスワードが違います", "Wrong email or password")
        case .userNotFound:
            return L("そのメールアドレスのアカウントが見つかりません", "No account for that email")
        case .userNotConfirmed:
            return L("メールに届いた確認コードで登録を完了してください", "Finish sign up with the code we emailed you")
        case .codeMismatch:
            return L("確認コードが違います", "That code is wrong")
        case .codeExpired:
            return L("確認コードの有効期限が切れています。再送してください", "That code expired. Send a new one.")
        case .limitExceeded:
            return L("回数が多すぎます。しばらく待ってからお試しください", "Too many attempts. Please wait and try again.")
        case .network:
            return Labels.Common.unreachable
        case .passwordResetRequired:
            // Web と同じ案内（`lib/auth/cognito.ts`）
            return L("パスワードの再設定が必要です。「パスワードを忘れた」から再設定してください",
                     "You need to reset your password. Use \"Forgot password?\" to set a new one.")
        case .signInIncomplete:
            return L("このアカウントはアプリからログインを完了できません。Web からログインしてください",
                     "This account can't finish signing in from the app. Please sign in on the web.")
        case .alreadySignedIn:
            return L("前のログインがこの端末から消せていません。アプリを終了して開き直してから、もう一度ログインしてください",
                     "A previous sign-in couldn't be cleared from this device. Quit and reopen the app, then sign in again.")
        case .none, .other:
            return L("うまくいきませんでした。しばらくしてからもう一度お試しください", "That didn't work. Please try again in a moment.")
        }
    }
}
