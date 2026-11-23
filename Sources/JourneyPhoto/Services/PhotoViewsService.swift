import Foundation

/// **写真の閲覧数**（札 #707・owner 承認 2026-11-23「推奨でお願い」・案の頁「写真の閲覧数」版4）。
///
/// - 送る: 写真の詳細が1秒以上見えたら `POST /photos/{id}/view`（未認証・`{"via":"app"}`）。
///   同じ写真はこの端末で30分以内なら送らない・本人のときは送らない・圏外では送らない（貯めない）・
///   ログインの確かめが終わるまで待つ。ホームの並びや一覧では送らない（詳細だけ）
/// - 読む: 持ち主だけ。写真ごとは `GET /user/photos/{id}/views`、マイページの累計は
///   `GET /user/photos/views?ids=`（100枚ずつ）を読んで端末で足す
/// - 数えるかどうか（公開・ストーリー・機械）はサーバーが決める（photo-gallery の `api-user/src/photoViews.ts`）
struct PhotoViewsService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// まとめて読む口が1回に受ける写真の数（サーバーの `MAX_IDS`）
    static let batchSize = 100

    private struct Body: Encodable { let via: String }
    private struct Many: Decodable { let views: [String: Part] }
    private struct Part: Decodable { let app: Int?; let web: Int? }

    /// 送る。送れたら true（数えたかどうかはサーバーが決める）
    func record(photoId: String) async -> Bool {
        do {
            _ = try await api.anonymous(.post, "/photos/\(PathID.segment(photoId))/view",
                                        body: Body(via: "app"), as: EmptyResponse.self)
            return true
        } catch {
            return false
        }
    }

    /// 1枚の閲覧数（持ち主だけ。他人の写真・無い写真は 404 で投げる）
    func counts(photoId: String) async throws -> PhotoViewCounts {
        try await api.authorized(.get, "/user/photos/\(PathID.segment(photoId))/views", as: PhotoViewCounts.self)
    }

    /// 自分の写真の累計（100枚ずつ読んで足す）。1回でも読めなければ投げる（足りない数を出さない）
    func total(photoIds: [String]) async throws -> Int {
        let ids = PhotoViews.uniqueSafeIds(photoIds)
        var sum = 0
        for start in stride(from: 0, to: ids.count, by: Self.batchSize) {
            let chunk = ids[start..<min(start + Self.batchSize, ids.count)]
            let page = try await api.authorized(.get, "/user/photos/views",
                                                query: ["ids": chunk.joined(separator: ",")], as: Many.self)
            sum += page.views.values.reduce(0) { $0 + max(0, $1.app ?? 0) + max(0, $1.web ?? 0) }
        }
        return sum
    }
}

/// `GET /user/photos/{id}/views` の答え
struct PhotoViewCounts: Decodable, Equatable {
    let app: Int
    let web: Int
    let total: Int
    /// 初めて数えた日（日本時間の "YYYY-MM-DD"）。まだ0回なら nil
    let since: String?

    init(app: Int, web: Int, since: String?) {
        self.app = max(0, app)
        self.web = max(0, web)
        self.total = self.app + self.web
        self.since = since
    }

    init(from decoder: Decoder) throws {
        struct Raw: Decodable { let app: Int?; let web: Int?; let since: String? }
        let raw = try Raw(from: decoder)
        self.init(app: raw.app ?? 0, web: raw.web ?? 0, since: raw.since)
    }
}

/// 画面の言葉・数の書き方・状態（画面を持たない層・Linux の試験で守る）
enum PhotoViews {

    /// 同じ写真を重ねて送らない時間（30分・プライバシーポリシーの本文と同じ）
    static let dedupInterval: TimeInterval = 30 * 60
    /// 見えてから送るまで
    static let dwellNanoseconds: UInt64 = 1_000_000_000
    /// 数え上げの長さ（シートを開いたとき・視差効果を減らす設定では数え上げない）
    static let countUpSeconds: Double = 0.6

    // MARK: 数の書き方

    /// 「1,234」「1万2,480」（1万以上は万で区切る・案の頁 版4）。英語は「12,480」
    static func number(_ n: Int, language: String = Locale.preferredAppLanguage) -> String {
        let n = max(0, n)
        guard language != "en", n >= 10_000 else { return grouped(n) }
        let man = n / 10_000
        let rest = n % 10_000
        return rest == 0 ? "\(grouped(man))万" : "\(grouped(man))万\(grouped(rest))"
    }

    /// 「1,234回」「1万2,480回」。英語は数だけ
    static func times(_ n: Int, language: String = Locale.preferredAppLanguage) -> String {
        let s = number(n, language: language)
        return language == "en" ? s : "\(s)回"
    }

    private static func grouped(_ n: Int) -> String {
        let digits = Array(String(n))
        var out = ""
        for (i, c) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(c)
        }
        return out
    }

    /// アプリの割合（%）。Web は 100 から引く（足して 100 になる）。0回なら nil
    static func appPercent(_ c: PhotoViewCounts) -> Int? {
        guard c.total > 0 else { return nil }
        return Int((Double(c.app) * 100 / Double(c.total)).rounded())
    }

    /// 「2026年12月1日から数えています」。読めない日付は nil（行ごと出さない）
    static func sinceLine(_ since: String?, language: String = Locale.preferredAppLanguage) -> String? {
        guard let since else { return nil }
        let parts = since.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        if language == "en" {
            let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            return "Counting since \(months[parts[1] - 1]) \(parts[2]), \(parts[0])"
        }
        return "\(parts[0])年\(parts[1])月\(parts[2])日から数えています"
    }

    // MARK: 言葉

    static var label: String { L("閲覧数", "Views") }
    static var zero: String { L("まだ閲覧されていません", "No views yet") }
    static var failed: String { L("閲覧数を読み込めませんでした", "Couldn't load views") }
    static var retry: String { L("再読み込み", "Reload") }
    static var offline: String { L("圏外のため、閲覧数は出せません", "Views aren't available offline") }
    static var onlyYou: String { L("閲覧数は、あなたにだけ見えます", "Only you can see views") }
    static var totalHeading: String { L("これまでの閲覧数", "Total views") }
    static var note: String {
        L("見た人の名前は分かりません。同じ人が30分以内に開き直した分は数えません。",
          "Viewers' names aren't recorded. Reopening within 30 minutes isn't counted again.")
    }
    static var shareLink: String { L("リンクを送って見てもらう", "Share the link") }
    static var app: String { L("アプリ", "App") }
    static var web: String { L("Web", "Web") }
    /// 大きな数の横の単位（英語は数だけなので無し）
    static var unit: String? {
        let u = L("回", "")
        return u.isEmpty ? nil : u
    }
    static var myPageLabel: String { L("累計閲覧数", "Total views") }

    // MARK: 写真の詳細の1行の状態

    enum RowState: Equatable {
        case loading
        case loaded(PhotoViewCounts)
        case failed
        case offline
    }

    /// 1行の状態。**読めた数は圏外になっても残す**（分かっている数を消さない）。読めていなくて圏外なら圏外の言葉
    static func rowState(counts: PhotoViewCounts?, failed: Bool, offline: Bool) -> RowState {
        if let counts { return .loaded(counts) }
        if offline { return .offline }
        return failed ? .failed : .loading
    }

    /// 1行の文（読み上げも同じ）。読み込み中は nil（骨組みを出す）
    static func rowText(_ state: RowState, language: String = Locale.preferredAppLanguage) -> String? {
        switch state {
        case .loading: return nil
        case .loaded(let c):
            return c.total == 0 ? L(zeroJA, zeroEN, language: language)
                : "\(L("閲覧数", "Views", language: language)) \(times(c.total, language: language))"
        case .failed: return L("閲覧数を読み込めませんでした", "Couldn't load views", language: language)
        case .offline: return L("圏外のため、閲覧数は出せません", "Views aren't available offline", language: language)
        }
    }
    private static let zeroJA = "まだ閲覧されていません"
    private static let zeroEN = "No views yet"

    /// 1行を押して内訳のシートを開けるか（1回以上読めたときだけ。0回は押せない1行・owner 2026-11-23「これいらないな」）
    static func opensSheet(_ state: RowState) -> Bool {
        if case .loaded(let c) = state { return c.total > 0 }
        return false
    }

    // MARK: 送る条件

    /// 送ってよいか: 本人でない・ログインの確かめが済んだ・圏外でない・UI テストの見本の利用者でない
    static func mayRecord(isMine: Bool, signInResolving: Bool, offline: Bool, previewSession: Bool) -> Bool {
        !isMine && !signInResolving && !offline && !previewSession
    }

    /// 重なりを落とした、パスに入れてよい ID だけ
    static func uniqueSafeIds(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { PathID.isSafe($0) && seen.insert($0).inserted }
    }
}

/// 同じ写真を30分以内に重ねて送らないための控え（端末の中だけ・写真の ID と送った時刻）
struct PhotoViewSendLog {

    static let key = "photoViews.sent.v1"
    /// 覚えておく写真の数（古い順に捨てる）
    static let maxEntries = 200

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var entries: [String: Double] {
        (defaults.dictionary(forKey: Self.key) as? [String: Double]) ?? [:]
    }

    /// 今送ってよいか（30分以内に送っていない）
    func shouldSend(_ photoId: String, now: Date) -> Bool {
        guard let last = entries[photoId] else { return true }
        let age = now.timeIntervalSince1970 - last
        return !(age >= 0 && age < PhotoViews.dedupInterval)
    }

    /// 送れたときだけ書く
    func markSent(_ photoId: String, now: Date) {
        var e = entries
        e[photoId] = now.timeIntervalSince1970
        if e.count > Self.maxEntries {
            e = Dictionary(uniqueKeysWithValues: e.sorted { $0.value > $1.value }.prefix(Self.maxEntries).map { ($0.key, $0.value) })
        }
        defaults.set(e, forKey: Self.key)
    }
}
