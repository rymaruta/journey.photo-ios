import Foundation

// Linux では URLSession が別モジュールに居る（`PublicGalleryService` と同じ理由）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 撮影スポットの索引（`app/data/spots.json`）。
///
/// **API ではなく、静的サイトに置かれた JSON を読む。** Web の
/// `content/spots.json`（人が持つ台帳）から、Next のルートハンドラが
/// アプリ向けの薄い索引を書き出し、サイト直下に配る。写真の一覧
/// （`PublicGalleryService`）と同じ4段で読む:
///
///     控え（60秒） → 通信 → 圏外なら前回のぶん → 読めなければ前回のぶん
///
/// 違いは**取れなくても写真の機能を止めない**こと。本番は Web の変更が
/// `main` に入るまでこの URL が 404 で、そのあいだ地図はスポットのピンを
/// 出さないだけ——呼ぶ側（`PhotoMapViewModel`）は `try?` で受ける。
///
/// **404 だけは控えに落とさない。** 404 は「索引を下げた」なので、空を返して
/// 控えも消す（下げたものを圏外で出し続けない）。5xx（サーバーの都合）と
/// 圏外は控えがあればそれを出す。
///
/// **スポットのための API は足していない**（`AppConfig.publicSpotsURL` の注記）。
///
/// ## 分けた置き場（2026-10-07）
///
/// 数千〜数万件に増やすため、Web は**軽い索引**（`spot-feed/index.json`・全件）と**区分ごとの詳細**
/// （`spot-feed/<区分>.json`・行は `spots.json` と同じ）に分けて配る。古い `spots.json` は
/// 2026-10-07 の行で固定。このサービスは**索引を先に読み**、詳細は要る区分だけ後から重ねる
/// （`withDetails`・詳細の和が小さいうちは全区分）。分けた置き場が無い Web なら `spots.json` に戻る。
/// 設計は photo-gallery の `docs/spot-feed-sharding.md`
actor OfficialSpotService {

    private let url: URL
    private let session: URLSession
    private let snapshot: SpotSnapshotStore
    /// 索引の要求を出す**直前**に待つ口。**本番は nil**（何もしない）。
    /// 試験が「索引が遅い回」を作るのに使う（`PublicGalleryService` の
    /// `beforeLiveRequest` と同じ理由）
    private let beforeRequest: (@Sendable () async -> Void)?
    /// 取れた本文を使い回す長さ。**短く**（下書きに戻した・文を直した場所の古い本文を出し続けない）
    let bodyLifetime: TimeInterval
    /// 「無い（404）」を覚える長さ。こちらは長くてよい（無いものを開くたびに叩かない）。
    /// 読めない中身は 404 と違い一時的なことがあるので、`bodyLifetime` で覚える
    let missingBodyLifetime: TimeInterval

    /// 分けた置き場の索引（`spot-feed/index.json`）。**nil なら古い置き場だけを読む**（`splitFeed`）
    private let feedIndexURL: URL?
    /// 分けた置き場の控えの名前の頭（`<頭>-index.json`・`<頭>-<区分>.json`）
    private let feedSnapshotPrefix: String
    /// 詳細の和（索引の `shards[].bytes` の和）がこれ以下なら、索引のあと**全区分を読む**
    let detailPrefetchBudget: Int

    /// - Parameters:
    ///   - splitFeed: 分けた置き場（`url` の隣の `spot-feed/index.json`・本番は
    ///     `AppConfig.publicSpotFeedIndexURL` と同じ）を先に読むか。false なら古い置き場だけ（試験用）
    init(url: URL = AppConfig.publicSpotsURL,
         session: URLSession? = nil,
         snapshot: SpotSnapshotStore = SpotSnapshotStore(),
         beforeRequest: (@Sendable () async -> Void)? = nil,
         bodyLifetime: TimeInterval = OfficialSpotService.cacheLifetime,
         missingBodyLifetime: TimeInterval = OfficialSpotService.cacheLifetime * 10,
         splitFeed: Bool = true,
         feedSnapshotPrefix: String = "spot-feed",
         detailPrefetchBudget: Int = OfficialSpotService.detailPrefetchBudget) {
        self.url = url
        self.feedIndexURL = splitFeed
            ? url.deletingLastPathComponent().appendingPathComponent("spot-feed").appendingPathComponent("index.json")
            : nil
        self.feedSnapshotPrefix = feedSnapshotPrefix
        self.detailPrefetchBudget = detailPrefetchBudget
        self.snapshot = snapshot
        self.beforeRequest = beforeRequest
        self.bodyLifetime = bodyLifetime
        self.missingBodyLifetime = missingBodyLifetime
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = APIClient.requestTimeout
            // 索引は `public, max-age=3600` で配られるが、端末側の控えは
            // 自分で持つ（`snapshot` と版の印）ので、URLSession には溜めさせない
            // （要求の側でも付けている——`ConditionalGet.plainRequest`）
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config)
        }
    }

    /// 直前に取れた索引と、その時刻。**短い間だけ使い回す**
    /// （地図を開くたびに 1,400件を落とし直さない）
    private var cached: [OfficialSpot]?
    private var cachedAt: Date?
    static let cacheLifetime: TimeInterval = 60

    private var freshCache: [OfficialSpot]? {
        guard let cached, let cachedAt,
              Date().timeIntervalSince(cachedAt) < Self.cacheLifetime else { return nil }
        return cached
    }

    /// - Parameter force: 控えを無視して取り直す（引き下げ更新）。
    ///
    /// **分けた置き場（`spot-feed/index.json`・2026-10-07）を先に読む。** 返す行は索引の行で、
    /// 読めている区分の詳細を重ねたもの（`withLoadedDetails`）。詳細の和が小さいうち
    /// （`detailPrefetchBudget` 以下）は全区分をここで読む——画面の見え方は古い置き場と同じ。
    /// 超えたら、要る画面が `withDetails` で要る区分だけ読む。
    ///
    /// **分けた置き場が無い（404）・知らない版・読めず控えも無い**ときは、今までどおり
    /// 古い置き場（`spots.json`）を読む（新しい置き場をまだ出していない Web）
    func fetchIndex(force: Bool = false) async throws -> [OfficialSpot] {
        if !force, let fresh = freshCache { return withLoadedDetails(fresh) }
        await beforeRequest?()
        if let feedIndexURL, let rows = await fetchFeedIndex(feedIndexURL) {
            cached = rows
            cachedAt = Date()
            let keys = Set(shardTable.keys)
            await loadShards(keys, network: totalDetailBytes <= detailPrefetchBudget)
            return withLoadedDetails(rows)
        }
        resetFeedState()
        return try await fetchLegacyIndex()
    }

    /// 古い置き場（`spots.json`・1ファイルに全部）。**2026-10-07 の行で固定**されている
    private func fetchLegacyIndex() async throws -> [OfficialSpot] {
        let data: Data
        let response: URLResponse
        do {
            try RequestCancellation.throwIfCancelled()
            // **条件付きで取る**（`ConditionalGet`・写真の一覧と同じ部品）。
            // 変わっていなければ 304 で、端末の控えを使う
            let snapshot = self.snapshot
            let outcome = try await ConditionalGet.fetch(url, session: session, validators: snapshot.validators) {
                snapshot.load()
            }
            switch outcome {
            case .notModified(let spots):
                cached = spots
                cachedAt = Date()
                return spots
            case .fetched(let body, let reply):
                (data, response) = (body, reply)
            }
        } catch {
            // **圏外なら前回のぶんを出す。** 出せなければそのとき初めて諦める
            if let cached = snapshot.load() { return cached }
            throw APIError.unreachable
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.decoding("HTTP 応答ではありません")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 404 {
                // 索引が無い＝下げた。古い控えを出さず、控えも消す。
                // 60秒は「無い」を覚える（地図を開くたびに叩き直さない）
                snapshot.clear()
                cached = []
                cachedAt = Date()
                return []
            }
            if let cached = snapshot.load() { return cached }
            throw APIError.server(status: http.statusCode, message: "")
        }
        // **200 の HTML は読もうとする前に退ける。** キャプティブポータル
        // （ホテル・空港の Wi-Fi）は JSON の要求にも 200 でログイン画面を返す。
        // 中身の復号で弾けることが多いが、種別が言っているなら先に信じる
        // ——控えに落とすと、次から圏外でその HTML が「索引」として出る
        if Self.isHTML(http) {
            print("[spots] 索引の応答が HTML でした（キャプティブポータルの可能性）")
            if let cached = snapshot.load() { return cached }
            throw APIError.decoding("索引の応答が HTML でした")
        }
        do {
            let list = try JSONDecoder.api.decode(LenientOfficialSpotList.self, from: data)
            if list.dropped > 0 {
                // 黙って捨てない。**どの行が出ていないのか**を追えるように
                print("[spots] 読めなかった・重複した索引の行を \(list.dropped) 件落としました")
            }
            let spots = list.spots
            // **読めたものだけを控える。** 1件も読めなかった回も控えない
            // ——前回の良い控えを空で上書きしない（本当に0件なら dropped も0）
            if !spots.isEmpty || list.dropped == 0 {
                snapshot.save(data, validator: HTTPValidator(response: http))
            } else {
                // 控えていない中身の印を残さない（`PublicGalleryService` と同じ）
                snapshot.validators.clear()
            }
            cached = spots
            cachedAt = Date()
            return spots
        } catch {
            if let cached = snapshot.load() { return cached }
            throw APIError.decoding(String(describing: error))
        }
    }

    // MARK: - 分けた置き場（`/app/data/spot-feed/`・2026-10-07）

    /// 詳細の和の既定の上限。2026-10-07 の公開 1,079件で詳細の和は約 0.9MB（古い `spots.json` と同じ量）。
    /// これを超えるまでは全区分を読み、画面の見え方を今と変えない
    static let detailPrefetchBudget = 1_500_000

    /// 索引の区分の表（鍵 → 大きさ・指紋）
    struct ShardInfo: Equatable, Sendable {
        let bytes: Int
        /// 区分のファイルの指紋（`ValidatorStore.fingerprint` と同じ式）。合う控えなら取りに行かない
        let hash: String?
    }

    /// 読めた索引（`ConditionalGet` で控えから読むときも同じ形）
    struct ParsedFeedIndex: Sendable {
        let rows: [OfficialSpot]
        let table: [String: ShardInfo]
        let aliases: [String: [String]]
        let dropped: Int
    }

    /// 索引の読み方の結果
    enum FeedIndexDecoding: Sendable {
        case ok(ParsedFeedIndex)
        /// 知らない版（`v`）。**古い置き場に戻る**
        case unknownVersion
        /// 読めない中身
        case broken
    }

    /// 分けた置き場が言う版。形を互換なしに変えたら Web が上げる
    static let feedVersion = 1

    private var shardTable: [String: ShardInfo] = [:]
    /// 読めた区分の詳細（`spotId` → 行）と、そのとき索引が言っていた指紋
    private var details: [String: (rows: [String: OfficialSpot], hash: String?)] = [:]
    /// 走っている区分の読み込み（区分ごとに1本）
    private var shardLoads: [String: Task<ShardDownload, Never>] = [:]
    /// 取れなかった区分を叩き直さない時刻
    private var shardRetryAt: [String: Date] = [:]
    /// 索引の別名（slug → 別名）。分けた置き場を読めた回だけ
    private var indexAliases: [String: [String]]?

    private var totalDetailBytes: Int { shardTable.values.reduce(0) { $0 + $1.bytes } }

    private func resetFeedState() {
        shardTable = [:]
        details = [:]
        indexAliases = nil
    }

    /// 索引を読む。**nil は「分けた置き場は使えない」＝古い置き場へ**
    private func fetchFeedIndex(_ indexURL: URL) async -> [OfficialSpot]? {
        let store = SpotSnapshotStore(fileName: "\(feedSnapshotPrefix)-index.json")
        func fromSnapshot() -> [OfficialSpot]? {
            guard let data = store.loadData(), case .ok(let parsed) = Self.decodeFeedIndex(data) else { return nil }
            return adopt(parsed)
        }
        do {
            try RequestCancellation.throwIfCancelled()
            let outcome: ConditionalGet.Outcome<ParsedFeedIndex> = try await ConditionalGet.fetch(
                indexURL, session: session, validators: store.validators
            ) { () -> ParsedFeedIndex? in
                guard let data = store.loadData(), case .ok(let parsed) = Self.decodeFeedIndex(data) else { return nil }
                return parsed
            }
            switch outcome {
            case .notModified(let parsed):
                return adopt(parsed)
            case .fetched(let data, let response):
                guard let http = response as? HTTPURLResponse else { return fromSnapshot() }
                if http.statusCode == 404 {
                    // 分けた置き場が無い（まだ出していない・下げた）。控えを出し続けない
                    store.clear()
                    return nil
                }
                guard (200..<300).contains(http.statusCode), !Self.isHTML(http) else { return fromSnapshot() }
                switch Self.decodeFeedIndex(data) {
                case .ok(let parsed):
                    if parsed.dropped > 0 {
                        print("[spots] 読めなかった・重複した索引の行を \(parsed.dropped) 件落としました")
                    }
                    // 読めたものだけを控える（1件も読めなかった回は控えない・古い置き場と同じ判断）
                    if !parsed.rows.isEmpty || parsed.dropped == 0 {
                        store.save(data, validator: HTTPValidator(response: http))
                    } else {
                        store.validators.clear()
                    }
                    return adopt(parsed)
                case .unknownVersion:
                    // このアプリが知らない形。**古い置き場に戻る**（控えた古い版も出さない）
                    print("[spots] 分けた置き場の索引が知らない版でした。古い置き場を読みます")
                    store.clear()
                    return nil
                case .broken:
                    print("[spots] 分けた置き場の索引が読めませんでした")
                    return fromSnapshot()
                }
            }
        } catch {
            // 圏外。控えがあればそれ、無ければ古い置き場（その控え）へ
            return fromSnapshot()
        }
    }

    /// 読めた索引を持つ。**指紋の変わった区分の詳細は捨てる**（下げた写真・直した文を出し続けない）
    private func adopt(_ parsed: ParsedFeedIndex) -> [OfficialSpot] {
        shardTable = parsed.table
        indexAliases = parsed.aliases
        details = details.filter { key, value in
            guard let info = parsed.table[key] else { return false }
            return value.hash != nil && value.hash == info.hash
        }
        return parsed.rows
    }

    /// 索引の JSON を読む（純関数・試験からも呼ぶ）。行は区分ごとにまとまっている
    static func decodeFeedIndex(_ data: Data) -> FeedIndexDecoding {
        struct Head: Decodable { let v: Int }
        struct File: Decodable { let shards: [Lenient<Shard>] }
        struct Shard: Decodable {
            let key: String
            let bytes: Int?
            let hash: String?
            let spots: LenientOfficialSpotList
        }
        guard let head = try? JSONDecoder.api.decode(Head.self, from: data) else { return .broken }
        guard head.v == feedVersion else { return .unknownVersion }
        guard let file = try? JSONDecoder.api.decode(File.self, from: data) else { return .broken }
        var rows: [OfficialSpot] = []
        var table: [String: ShardInfo] = [:]
        var aliases: [String: [String]] = [:]
        var seen = Set<String>()
        var dropped = 0
        for shard in file.shards.compactMap(\.value) {
            // 区分の鍵はパスに混ぜる。綴りが違えば区分ごと落とす（行も地図に出さない）
            guard isSafeKey(shard.key), table[shard.key] == nil else {
                dropped += shard.spots.spots.count + shard.spots.dropped
                continue
            }
            table[shard.key] = ShardInfo(bytes: max(0, shard.bytes ?? 0), hash: shard.hash)
            dropped += shard.spots.dropped
            for var row in shard.spots.spots {
                // 区分をまたいだ同じ `spotId` も先勝ち（`LenientOfficialSpotList` と同じ理由）
                guard seen.insert(row.spotId).inserted else { dropped += 1; continue }
                row.shard = shard.key
                row.isIndexOnly = true
                if let names = row.aliases?.value, !names.isEmpty { aliases[row.slug] = names }
                rows.append(row)
            }
        }
        return .ok(ParsedFeedIndex(rows: rows, table: table, aliases: aliases, dropped: dropped))
    }

    /// 区分の鍵として使ってよい綴り（`[a-z0-9-]`・空でない）
    static func isSafeKey(_ key: String) -> Bool {
        !key.isEmpty && key.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
    }

    /// 索引の行に、読めている区分の詳細を重ねる（通信しない）
    private func withLoadedDetails(_ rows: [OfficialSpot]) -> [OfficialSpot] {
        guard !details.isEmpty else { return rows }
        return rows.map { row in
            guard row.isIndexOnly, let key = row.shard, let detail = details[key]?.rows[row.spotId] else { return row }
            return row.merged(with: detail)
        }
    }

    /// **渡した行（`spots`）に、`needed` の行の区分の詳細を読んで重ねて返す。**
    ///
    /// 写真・概要・季節/時間帯の文・時刻帯が要る画面（開いた場所・地図に見えているピン・
    /// ホームの札と段・行きたい場所・旅行プラン）が、**出す行だけ**を `needed` に渡す。
    /// 詳細を重ね済みの行・古い置き場の行は何もしない。取れなかった区分の行は索引のまま返す
    /// （投げない——写真や文が出ないだけ）
    func withDetails(_ spots: [OfficialSpot], for needed: [OfficialSpot]) async -> [OfficialSpot] {
        let keys = Set(needed.filter(\.isIndexOnly).compactMap(\.shard))
        guard !keys.isEmpty else { return withLoadedDetails(spots) }
        // 区分の表が無い（このサービスでまだ索引を読んでいない）なら先に読む
        if shardTable.isEmpty { _ = try? await fetchIndex() }
        await loadShards(keys, network: true)
        return withLoadedDetails(spots)
    }

    /// 区分を読む。`network` が false なら端末の控え（指紋が合うもの）だけ
    private func loadShards(_ keys: Set<String>, network: Bool) async {
        let wanted = keys.filter { key in
            guard let info = shardTable[key] else { return false }
            guard let loaded = details[key] else { return true }
            return loaded.hash == nil || loaded.hash != info.hash
        }
        guard !wanted.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for key in wanted {
                group.addTask { await self.loadShard(key, network: network) }
            }
        }
    }

    /// 区分のファイルの取れ方
    enum ShardDownload: Sendable {
        case fetched(Data)
        /// 404（割り直して無くなった区分）
        case missing
        /// 圏外・5xx・HTML
        case failed
    }

    private func shardSnapshot(_ key: String) -> SpotSnapshotStore {
        SpotSnapshotStore(fileName: "\(feedSnapshotPrefix)-\(key).json")
    }

    private func loadShard(_ key: String, network: Bool) async {
        guard let info = shardTable[key], Self.isSafeKey(key) else { return }
        let store = shardSnapshot(key)
        // 1) 端末の控えの指紋が索引と同じなら、それを使う（**通信しない**）
        if let hash = info.hash, let data = store.loadData(), ValidatorStore.fingerprint(data) == hash,
           let rows = Self.decodeShard(data) {
            details[key] = (rows, hash)
            return
        }
        guard network else { return }
        if let retry = shardRetryAt[key], Date() < retry { return }
        let load: Task<ShardDownload, Never>
        if let running = shardLoads[key] {
            load = running
        } else {
            // 🔴 **読み込みは区分ごとに1本に寄せ、呼んだ側の取り消しを受けない**（`fetchAliases` と同じ理由）
            let shardURL = (feedIndexURL ?? url).deletingLastPathComponent().appendingPathComponent("\(key).json")
            let session = self.session
            load = Task {
                let request = URLRequest(url: shardURL, cachePolicy: .reloadIgnoringLocalCacheData)
                guard let (data, response) = try? await session.data(for: request),
                      let http = response as? HTTPURLResponse else { return .failed }
                if http.statusCode == 404 { return .missing }
                guard (200..<300).contains(http.statusCode), !Self.isHTML(http) else { return .failed }
                return .fetched(data)
            }
            shardLoads[key] = load
        }
        let result = await load.value
        shardLoads[key] = nil
        // 待っている間に索引が替わり、区分が無くなった・別の回が読み終えた
        guard let current = shardTable[key] else { return }
        if let loaded = details[key], loaded.hash != nil, loaded.hash == current.hash { return }
        switch result {
        case .fetched(let data):
            guard let rows = Self.decodeShard(data) else {
                print("[spots] 区分が読めませんでした: \(key)")
                shardRetryAt[key] = Date().addingTimeInterval(Self.cacheLifetime)
                useStaleShard(key, store: store)
                return
            }
            // 指紋が索引と合わなくても（CDN の入れ替わりの途中）、配られたものを出す。
            // 覚える指紋は索引のもの——次に索引が替わるまで取り直さない
            store.save(data, validator: nil)
            details[key] = (rows, current.hash)
            shardRetryAt[key] = nil
        case .missing:
            store.clear()
            details[key] = nil
            shardRetryAt[key] = Date().addingTimeInterval(Self.cacheLifetime)
        case .failed:
            shardRetryAt[key] = Date().addingTimeInterval(Self.cacheLifetime)
            useStaleShard(key, store: store)
        }
    }

    /// 取れなかった区分は、**指紋の合わない前回の控えでも出す**（圏外で地図の写真が消えない）。
    /// 印は付けない（次の機会に取り直す）
    private func useStaleShard(_ key: String, store: SpotSnapshotStore) {
        guard details[key] == nil, let data = store.loadData(), let rows = Self.decodeShard(data) else { return }
        details[key] = (rows, nil)
    }

    /// 区分の JSON（行は `spots.json` と同じ形）→ `spotId` → 行。読めなければ nil
    static func decodeShard(_ data: Data) -> [String: OfficialSpot]? {
        guard let list = try? JSONDecoder.api.decode(LenientOfficialSpotList.self, from: data) else { return nil }
        if list.dropped > 0 {
            print("[spots] 読めなかった・重複した区分の行を \(list.dropped) 件落としました")
        }
        return Dictionary(list.spots.map { ($0.spotId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - 本文（`/app/data/spots/<slug>.json`・2026-09-27）

    /// 取れた本文と、取れなかった（404）ことの控え。**開くたびに叩き直さない**
    /// 本文の控え。`until` を過ぎたら取り直す（本文・無い・読めない で長さが違う）
    private var bodies: [String: (body: SpotBody?, until: Date)] = [:]

    /// 撮影スポットの本文。索引の隣の `spots/<slug>.json`。
    ///
    /// **取れなければ nil**（まだ本番に無い 404・圏外・HTML・壊れた中身）。
    /// 画面は本文の節を出さないだけで、索引の内容はそのまま出す——投げない。
    /// 綴りが `[a-z0-9-]` でない slug は叩かない（パスに混ぜない）
    func fetchBody(slug: String) async -> SpotBody? {
        guard !slug.isEmpty, slug.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }) else {
            return nil
        }
        if let hit = bodies[slug], Date() < hit.until {
            return hit.body
        }
        let bodyURL = url.deletingLastPathComponent()
            .appendingPathComponent("spots")
            .appendingPathComponent("\(slug).json")
        let data: Data
        let response: URLResponse
        do {
            try RequestCancellation.throwIfCancelled()
            (data, response) = try await session.data(from: bodyURL)
        } catch {
            // 圏外は前回見た本文を出す（開き直すまでの間だけ・端末に書き残さない）
            return bodies[slug]?.body
        }
        guard let http = response as? HTTPURLResponse else { return nil }
        guard (200..<300).contains(http.statusCode), !Self.isHTML(http) else {
            if http.statusCode == 404 {
                // 無い（下書きに戻した・まだ出ていない）。**古い本文を出さない**
                bodies[slug] = (nil, Date().addingTimeInterval(missingBodyLifetime))
                return nil
            }
            return bodies[slug]?.body
        }
        guard let body = try? JSONDecoder.api.decode(SpotBody.self, from: data), body.slug == slug else {
            print("[spots] 本文が読めませんでした: \(slug)")
            // 読めない本文で前回のぶんを出し続けない。覚えるのは**本文と同じ短さ**——
            // 開くたびに取り直さないが、`text/html` を名乗らないログイン画面（キャプティブ
            // ポータル）を掴んだ回を10分引きずらない
            bodies[slug] = (nil, Date().addingTimeInterval(bodyLifetime))
            return nil
        }
        bodies[slug] = (body, Date().addingTimeInterval(bodyLifetime))
        return body
    }

    // MARK: - 別名（`/app/data/spot-search.json`・2026-09-30）

    /// 別名の控え（slug → 別名）と、取れた／取れなかった時刻。
    private var aliasCache: (map: [String: [String]], until: Date)?
    /// 別名を使い回す長さ。台帳の別名はめったに変わらない
    static let aliasLifetime: TimeInterval = 600
    /// 取れなかったときに叩き直さない長さ
    static let aliasRetryAfter: TimeInterval = 60

    /// 撮影スポットの別名（slug → 別名の一覧）。**Web の「さがす」が読む名前だけの索引**
    /// （`spot-search.json`・`lib/data/spotSearchFeed.ts`）を読む。索引（`spots.json`）には載っていない。
    ///
    /// **取れなければ空**（投げない）。別名は当たりを良くするおまけで、無くても名前・読みで引ける。
    /// 圏外・404・HTML・壊れた中身はどれも空（前に取れていればそれを使う）
    func fetchAliases() async -> [String: [String]] {
        // 分けた置き場の索引は別名を持つ（2026-10-07）。読めていれば `spot-search.json` は読まない
        if let indexAliases { return indexAliases }
        if let hit = aliasCache, Date() < hit.until { return hit.map }
        // 🔴 **読み込みは1本に寄せ、呼んだ側の取り消しを受けない。** 「さがす」は打つたびに
        // 呼ぶ側（`.task(id: query)`）が取り消されるので、取り消しを失敗と数えて空を1分控え、
        // その間は別名が一切当たらなかった。並んだ呼び出しが別々に叩き、遅れた失敗が先の成功を
        // 古い値で上書きすることもあった（47b7180 のレビュー）
        if aliasLoad == nil {
            let aliasURL = url.deletingLastPathComponent().appendingPathComponent("spot-search.json")
            let session = self.session
            aliasLoad = Task {
                guard let (data, response) = try? await session.data(from: aliasURL),
                      let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode), !Self.isHTML(http) else { return nil }
                return Self.aliases(from: data)
            }
        }
        let loaded = await aliasLoad?.value
        aliasLoad = nil
        // 待っている間に別の呼び出しが控えを書いていたら、それを使う
        if let hit = aliasCache, Date() < hit.until { return hit.map }
        if let map = loaded.flatMap({ $0 }) {
            aliasCache = (map, Date().addingTimeInterval(Self.aliasLifetime))
            return map
        }
        let previous = aliasCache?.map ?? [:]
        aliasCache = (previous, Date().addingTimeInterval(Self.aliasRetryAfter))
        return previous
    }

    /// 走っている別名の読み込み（1本だけ）
    private var aliasLoad: Task<[String: [String]]?, Never>?

    /// `spot-search.json` の行（`{ s: slug, n: 名前, a?: 別名[] }` ほか）から slug → 別名。
    /// 読めなければ nil。**読めない行・空の別名は落とす**（行ごと・中身ごと捨てない）
    static func aliases(from data: Data) -> [String: [String]]? {
        struct Row: Decodable { let s: String; let a: [String]? }
        guard let rows = try? JSONDecoder().decode([Lenient<Row>].self, from: data) else { return nil }
        var map: [String: [String]] = [:]
        for row in rows.compactMap(\.value) {
            let names = (row.a ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !row.s.isEmpty, !names.isEmpty { map[row.s] = names }
        }
        return map
    }

    /// `Content-Type` が `text/html` か。鍵の大小は見ない（サーバーによって違う）
    private static func isHTML(_ response: HTTPURLResponse) -> Bool {
        for (key, value) in response.allHeaderFields {
            guard let name = key as? String, name.lowercased() == "content-type",
                  let type = value as? String else { continue }
            return type.lowercased().hasPrefix("text/html")
        }
        return false
    }
}
