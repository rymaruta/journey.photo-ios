import Foundation
import Amplify

/// **ログアウトした時と道**を、端末の中だけに残す（2026-11-15 判断・札 #617）。
///
/// owner の報告「勝手にログアウトしちゃうのいやだ」で、どの道でログアウトしたかを数字で取るための記録。
/// `ExitTrail`（札 #596）と同じ置き場・同じ出口を使う:
///
/// - 書くのは**決まった道の名前・エラーの種類（型の名前）・ログインしてからの日数・版・時刻**だけ。
///   利用者 ID・メールアドレス・トークン・エラーの文（中に名前が入りうる）は入れない
/// - 端末の中だけ（`UserDefaults`）。**外へ出るのは、利用者が「意見を送る」で添えたときだけ**（`FeedbackSheet`）。
///   ログインし直しても消さない（入り直してから「意見を送る」で添えられるように）
/// - 道ごとの回数も数える（`signOutCounts`）。直近の行は `signOutLinesMax` 行まで
/// - 「ログインしてからの日数」は ID トークンの `auth_time`（パスワードで入った時刻。更新しても変わらない）から出す。
///   更新トークンの期限（本番は 2026-11-15 まで 5 日、その日に 3650 日へ変えた・札 #617 / #657）で切れたのかを見分けるため
extension ExitTrail {

    /// ログアウトの道（決まった名前だけを書く）
    enum SignOutCause: String, CaseIterable, Equatable {
        /// 本人が押した（メニュー・設定）
        case user = "user"
        /// トークンを取ろうとしたら Cognito が「もう使えない」と答えた（`AuthGateway.idToken`）
        case expiredToken = "expired.token"
        /// サーバーの 401 のあと取り直したら、取り直せなかった（`APIClient.send`）
        case expiredRefresh = "expired.refresh"
        /// 取り直した鍵でもサーバーが 401 を返した（`APIClient.send`）
        case expiredRetry = "expired.retry401"
        /// 起動の確かめで期限切れが分かった（`AuthStore.restore`）
        case expiredLaunch = "expired.launch"
        /// パスワードを変えようとしたら期限切れだった（`AuthStore.changePassword`）
        case expiredPassword = "expired.password"
        /// 前の起動ではログイン中だったのに、起動したら Amplify が「ログインしていない」と答えた（`AuthStore.restore`）
        case launchNotSignedIn = "launch.notSignedIn"
        /// 起動したら Amplify はログイン中と答えたのに、本人の ID が取れなかった（`AuthStore.restore`）
        case launchNoUserId = "launch.noUserId"
        /// 前のログアウトで端末から消せなかった印に従って、起動でログアウトした（`SignOutLatch`）
        case launchLatch = "launch.latch"
        /// 退会した
        case accountDeleted = "account.deleted"
        /// **ログアウトではない。** 起動した時に鍵束（キーチェーン）がまだ開いておらず、ログインの読み込みを
        /// 開くまで待った（`AuthGateway.configure`・2026-11-15 判断）
        case keychainWait = "launch.keychainWait"
    }

    static let signOutKey = "exitTrail.signOut"
    static let signOutCountsKey = "exitTrail.signOutCounts"
    static let sessionKey = "exitTrail.session"
    /// 直近の行をいくつまで残すか
    static let signOutLinesMax = 3
    /// 添える細かい種類（エラーの型の名前・口の形）の長さの上限
    static let detailMax = 80

    /// ログイン中かと、入った時刻（端末の中の控え。**人は残さない**）
    struct Session: Codable, Equatable {
        var signedIn: Bool
        /// ID トークンの `auth_time`（パスワードで入った時刻）。読めなければ nil
        var authTime: Date?
    }

    // MARK: - 書く

    /// ログアウトした（または `keychainWait` のような起動の出来事）を1行残し、道の回数を1つ進める。
    ///
    /// ログアウトの道なら「ログイン中」の控えも下ろす（次の起動で `launch.notSignedIn` を二重に数えない）
    static func keepSignOut(_ cause: SignOutCause, detail: String? = nil, defaults: UserDefaults = .standard,
                            now: Date = Date(), version: String = currentVersion) {
        let previous = session(defaults: defaults)
        var line = "\(version) \(isoString(now)) cause=\(cause.rawValue)"
        if let authTime = previous?.authTime {
            let days = max(0, now.timeIntervalSince(authTime)) / 86_400
            line += " age=\(String(format: "%.1f", days))d"
        }
        if let detail = detail.map(sanitize), !detail.isEmpty { line += " detail=\(detail)" }
        lock.lock()
        var lines = defaults.stringArray(forKey: signOutKey) ?? []
        lines.append(line)
        if lines.count > signOutLinesMax { lines.removeFirst(lines.count - signOutLinesMax) }
        defaults.set(lines, forKey: signOutKey)
        var counts = (defaults.dictionary(forKey: signOutCountsKey) as? [String: Int]) ?? [:]
        counts[cause.rawValue, default: 0] += 1
        defaults.set(counts, forKey: signOutCountsKey)
        lock.unlock()
        if cause != .keychainWait {
            writeSession(Session(signedIn: false, authTime: nil), defaults: defaults)
        }
    }

    /// ログイン中になった（起動の確かめ・ログイン）。`authTime` は ID トークンの `auth_time`
    static func noteSignedIn(authTime: Date?, defaults: UserDefaults = .standard) {
        writeSession(Session(signedIn: true, authTime: authTime), defaults: defaults)
    }

    // MARK: - 読む

    static func session(defaults: UserDefaults = .standard) -> Session? {
        lock.lock()
        let data = defaults.data(forKey: sessionKey)
        lock.unlock()
        return data.flatMap { try? JSONDecoder().decode(Session.self, from: $0) }
    }

    static func signOutLines(defaults: UserDefaults = .standard) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return defaults.stringArray(forKey: signOutKey) ?? []
    }

    static func signOutCounts(defaults: UserDefaults = .standard) -> [String: Int] {
        lock.lock(); defer { lock.unlock() }
        return (defaults.dictionary(forKey: signOutCountsKey) as? [String: Int]) ?? [:]
    }

    /// 添える文の「ログアウト」の部分（無ければ nil）。**回数の1行が先、行は新しい順**（添える文は上限で
    /// 後ろから切れるので、大事な方を前に置く）。例:
    /// `[ログアウトの回数] expired.token=2 user=1` と
    /// `[ログアウト] 1.1.93 (1) 2026-11-15T10:00:00Z cause=expired.token age=5.0d detail=sessionExpired/NotAuthorizedException`
    static func signOutSummary(lines: [String], counts: [String: Int]) -> String? {
        guard !lines.isEmpty || !counts.isEmpty else { return nil }
        var out: [String] = []
        if !counts.isEmpty {
            let joined = counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            out.append("[ログアウトの回数] \(joined)")
        }
        out += lines.reversed().map { "[ログアウト] \($0)" }
        return out.joined(separator: "\n")
    }

    // MARK: - エラーの種類

    /// エラーを**型と種類の名前だけ**にする（エラーの文は入れない。Cognito の文に名前が入りうる）。
    /// 例: `sessionExpired/NotAuthorizedException`・`service/URLError`
    static func errorKind(_ error: Error) -> String {
        if let auth = error as? AuthError {
            let name: String
            switch auth {
            case .configuration: name = "configuration"
            case .service: name = "service"
            case .unknown: name = "unknown"
            case .validation: name = "validation"
            case .notAuthorized: name = "notAuthorized"
            case .invalidState: name = "invalidState"
            case .signedOut: name = "signedOut"
            case .sessionExpired: name = "sessionExpired"
            }
            guard let underlying = auth.underlyingError else { return name }
            return "\(name)/\(typeName(underlying))"
        }
        return typeName(error)
    }

    /// 口の形（数字や長い id の入った区切りは `:id` にする）。例: `/user/photos/:id`
    static func pathShape(_ path: String) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map { part -> String in
            let text = String(part)
            let plain = text.count <= 24 && text.allSatisfy { ($0.isLetter && $0.isASCII) || $0 == "-" || $0 == "_" }
            return plain ? text : ":id"
        }
        return "/" + parts.joined(separator: "/")
    }

    // MARK: - 中身

    private static func typeName(_ value: Any) -> String {
        // 型の名前だけ（入れ子の型は最後の名前）。中の値は読まない
        let full = String(describing: type(of: value))
        return String(full.split(separator: ".").last ?? Substring(full))
    }

    private static func sanitize(_ text: String) -> String {
        let allowed = text.filter { ($0.isLetter && $0.isASCII) || $0.isNumber || "./_-:=".contains($0) }
        return String(allowed.prefix(detailMax))
    }

    private static func writeSession(_ value: Session, defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        lock.lock(); defer { lock.unlock() }
        defaults.set(data, forKey: sessionKey)
    }
}
