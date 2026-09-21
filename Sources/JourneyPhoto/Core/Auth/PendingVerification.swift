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
}
