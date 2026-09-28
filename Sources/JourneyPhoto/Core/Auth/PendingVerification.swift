import Foundation

/// 「登録したが、まだ確認コードを入れていない」人の控え。
///
/// **これが無いと、確認前にアプリを閉じた人は永久に入れない。**
/// Cognito のユーザー名は UUID（`AuthGateway.signUp`）で、確認コードの
/// 送り直しにはその UUID が要る。画面の `@State` にしか無かったので、
/// アプリを閉じた時点で消えていた:
///
///     登録 → アプリを閉じる → 開く → ログイン
///       → UserNotConfirmed（「コードで完了してください」と出るが入口が無い）
///     → 登録し直す → 「すでに登録されています」
///     → パスワード再設定も効かない（未確認のアカウントには送られない）
///
/// Web 版は同じ穴を `localStorage` の控えで塞いでいる
/// （`app/signup/page.tsx` の `savePending` / `lib/utils/pendingName.ts`）。
/// 同じ約束をそのまま写す——**24時間で切れる**・**メールアドレスごと**・
/// **小文字に揃える**。
enum PendingVerification {

    /// 控えの寿命。Web の `PENDING_TTL` と同じ24時間。
    static let ttl: TimeInterval = 24 * 60 * 60

    /// **小文字に揃える。** Cognito のメールエイリアスは大小を区別しないので、
    /// `Taro@Example.com` で登録して `taro@example.com` でログインが成立する。
    /// 生の入力を鍵にすると、その場合だけ控えを拾えず**行き止まりに戻る**。
    static func key(for email: String) -> String {
        "jp_verify_\(email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    /// 控えが生きているか。
    static func isFresh(savedAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(savedAt) < ttl && now >= savedAt.addingTimeInterval(-ttl)
    }
}

/// 端末に残す控え。
struct PendingVerificationStore {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private struct Entry: Codable {
        let username: String
        let savedAt: Date
        /// 登録のときに入れた表示名。**確認が済むまで預かる**
        /// （確認前にアプリを閉じても、名前を打ち直させない）
        var displayName: String?
    }

    func remember(email: String, username: String, displayName: String? = nil, now: Date = Date()) {
        let entry = Entry(username: username, savedAt: now,
                          displayName: displayName?.isEmpty == true ? nil : displayName)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        defaults.set(data, forKey: PendingVerification.key(for: email))
    }

    /// 生きている控えだけ返す。切れていたらその場で捨てる。
    func username(for email: String, now: Date = Date()) -> String? {
        let key = PendingVerification.key(for: email)
        guard let data = defaults.data(forKey: key),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
        guard PendingVerification.isFresh(savedAt: entry.savedAt, now: now) else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return entry.username
    }

    /// 預かっている表示名（**メールアドレスごと**——共有の端末で、
    /// 次にログインした別人の名前にしない。Web の `pendingNameKey` と同じ理由）。
    func displayName(for email: String, now: Date = Date()) -> String? {
        let key = PendingVerification.key(for: email)
        guard let data = defaults.data(forKey: key),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              PendingVerification.isFresh(savedAt: entry.savedAt, now: now) else { return nil }
        return entry.displayName
    }

    func forget(email: String) {
        defaults.removeObject(forKey: PendingVerification.key(for: email))
    }

    /// その登録（Cognito のユーザー名＝UUID）の控えを消す。
    ///
    /// **退会のときに使う。** 退会の画面はメールアドレスを知らないので、
    /// 控えの中身（ユーザー名）で探す。確認のあと名前を入れられなかった回
    /// （`SignInView.applyDisplayName`）は控えが残っている
    func forget(username: String) {
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix("jp_verify_") {
            guard let data = value as? Data,
                  let entry = try? JSONDecoder().decode(Entry.self, from: data),
                  entry.username == username else { continue }
            defaults.removeObject(forKey: key)
        }
    }
}

/// ログインに失敗したあと、確認への入口を出すか。
///
/// 🔴 **確認の済んでいない人が、確認画面へ戻れなかった。** 登録はメールアドレスを別名にして
/// いるので、未確認のうちは別名でログインできず、Cognito は `UserNotConfirmed` ではなく
/// 「違います」（NotAuthorized）や「見つかりません」（UserNotFound）で答えることがある
/// （確かめていない）。その回は `lastFailureWasUnconfirmed` が当たらず、確認画面から
/// 「ログインに戻る」を押した人の戻り道が無かった（入口の `verificationOffer` は一度も出ていなかった）
enum SignInRecovery {
    static func offersVerification(after failure: AuthFailure, hasPendingSignUp: Bool) -> Bool {
        guard hasPendingSignUp else { return false }
        return failure == .notAuthorized || failure == .userNotFound
    }
}
