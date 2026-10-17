import Foundation

/// **端末の写真から、投稿する前に旅の一冊を作る**（2026-10-16 owner 決定）。
///
/// 写真を許可した瞬間に、投稿しなくても自分の過去の旅が一冊ずつ棚に並ぶ。投稿は任意。
/// **サーバーには何も送らない**（費用を増やさない）。外へ出るのは、地名を引くための
/// おおよその位置（約1km・Apple の地図・**一冊につき1回**）だけ。
///
/// ## 重くしない（owner の強い条件）
///
/// - **画像は読まない。** `PHAsset` の撮影日時・位置・識別子だけ（`DeviceTripLibrary`）。
///   表紙は画面に出たときに小さく読む（`LibraryThumbView`・`PHCachingImageManager`）
/// - **一度読んだ所は端末に覚える**（`Index`・軽い要約だけ）。次からは前回より新しい写真だけ。
///   数が合わない（消した・一部の許可を選び直した）ときだけ、識別子で突き合わせる（`needsSweep`）
/// - **後ろで低い優先度、`chunkSize` 枚ずつ。** `publishEvery` 枚ごとに見つかった旅を棚に出す
/// - **読む上限**: 直近 `lookbackYears` 年・新しい方から `maxShots` 枚まで
///
/// ## 旅の分け方（2026-10-16 判断）
///
/// **`LibraryTrips.find` をそのまま使う**（「旅の写真からまとめて」と同じ規則・写しを作らない）。
/// 投稿していない山には家の近くの日常の写真が混ざるので、`TripBook.trips` の「日付だけで束ねる」
/// では毎日が一冊になる。家（いちばん多い約10kmの升）から 50km 以上離れた日を、
/// `TripBook.maxGapDays` の空きまでつないで一冊にする（`LibraryTrips` の注記）
///
/// ## 見える範囲（2026-10-16 判断）
///
/// - **本人のマイページだけ。** 人のプロフィールの旅の記録には出さない（`books(isMine:)`）。
///   一冊はサーバーの `Photo` にならないので、人の棚（`ProfileTravelRecord`）には元々入らない
/// - **「この一冊を送る」は出さない**（`canShare`）。共有の画像に端末の写真が載って外へ出る。
///   「端末の中だけ」と約束した写真なので、送りたければ投稿してから（投稿した一冊は今までどおり送れる）
/// - **投稿済みの日がある旅は出さない**（`LibraryTrips.postedDays`）。投稿した一冊が棚にあるので、
///   同じ旅が2冊に見える
enum DeviceTrips {

    // MARK: - 上限（2026-10-16 判断）

    /// 遡る年数。**「旅の写真からまとめて」と同じ3年（`PhotoLibrary.lookbackYears`）にそろえる**
    /// （2026-10-16 判断・確かめ役の指摘）。棚の一冊から「この旅の写真を投稿する」で同じ流れを開くので、
    /// 年数が割れると、棚にある旅が流れの一覧に無い・入口によって一覧が変わる。長い方（5年）に
    /// そろえるより、owner の「重くしない」に合う短い方を取った
    static var lookbackYears: Int { PhotoLibrary.lookbackYears }
    /// 覚える枚数の上限（新しい方から）。**5万枚**——要約は1枚 約100バイトで、5万枚でも 約5MB
    static let maxShots = 50_000
    /// 1回に読む枚数。読み終えるたびに少し休んで、画面の動きに譲る
    static let chunkSize = 500
    /// 区切りの間の休み（ナノ秒）。**30ms**
    static let chunkPauseNanos: UInt64 = 30_000_000
    /// 何枚読むごとに棚を描き直すか（見つかった旅から順に出す）
    static let publishEvery = 2_000
    /// 何枚読むごとに端末に書くか（途中で閉じても、次は続きから読む）
    static let saveEvery = 5_000
    /// 覚える位置の細かさ（小数第4位 ≒ 約11m）。旅の判定（50km・約10kmの升）には十分で、
    /// 端末に残す位置を細かくしすぎない
    static let coordinateScale = 10_000.0

    /// 読みの間の下限（秒）。**60秒**——変化の知らせ（iCloud の同期・編集）が続いても、
    /// 前の読みの始まりから60秒は次を始めない（`runDelay`）
    static let minRunInterval: TimeInterval = 60
    /// 変化の知らせから読むまでの待ち（秒）。続けて来る知らせを1回にまとめる
    static let changeDelay: TimeInterval = 3
    /// 識別子の突き合わせ（`needsSweep`）は**10分に1回まで**（`maySweep`）。消した写真の表紙が
    /// しばらく残るだけで、旅の並びはほとんど変わらない
    static let sweepInterval: TimeInterval = 10 * 60
    /// 突き合わせで知らない識別子がこれより多ければ、1枚ずつ引かずに頭から読み直す
    /// （一部の許可から全部の許可に替えた——知らない写真が数万枚になる）
    static let maxSweepReads = 2_000

    /// 変化の知らせを受けてから読み始めるまでの待ち。**前の読みの始まりから `minRunInterval`**、
    /// 少なくとも `changeDelay`
    /// 2026-10-16 判断: 経った時間は 0 未満にしない。端末の時計を戻すと負になり、待ちが
    /// 「60秒＋戻した分」（1日戻せば約1日）に延びて、新しい写真が棚に出なかった
    static func runDelay(lastRunStart: Date?, now: Date) -> TimeInterval {
        guard let lastRunStart else { return changeDelay }
        return max(changeDelay, minRunInterval - max(0, now.timeIntervalSince(lastRunStart)))
    }

    /// 突き合わせてよいか（前の突き合わせから `sweepInterval` 経った）
    static func maySweep(lastSweep: Date?, now: Date) -> Bool {
        guard let lastSweep else { return true }
        return now.timeIntervalSince(lastSweep) >= sweepInterval
    }

    /// 地名を引き直すまでの間。**1日**（一冊につき1回の約束・圏外で引けなかった一冊だけ翌日に1回）
    static let nameRetryAfter: TimeInterval = 24 * 60 * 60
    /// 1回の起動で引く地名の上限（Apple の地名引きは短い間に何度も呼ぶと断られる）
    static let maxLookupsPerRun = 30
    /// 地名を引く間の休み（ナノ秒）。**1.5秒**（1分に約40回まで）
    static let lookupPauseNanos: UInt64 = 1_500_000_000

    /// 何年前までを読むか
    static func since(now: Date) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .year, value: -lookbackYears, to: now) ?? now
    }

    /// 位置を `coordinateScale` に丸める
    static func rounded(_ value: Double?) -> Double? {
        value.map { ($0 * coordinateScale).rounded() / coordinateScale }
    }

    // MARK: - 端末に覚える要約

    /// 端末に覚えるもの。**写真の撮影日時・位置・識別子だけ**（画像・地名以外の文字は持たない）
    struct Index: Codable, Equatable {
        static let currentVersion = 1

        var version = Index.currentVersion
        /// 新しい順
        var shots: [LibraryShot] = []
        /// 読んだが旅に入れない写真（スクリーンショット・位置は持たない）。**数を合わせるためだけ**に覚える
        /// ——ライブラリの数と比べるとき（`needsSweep`）、これが無いと毎回数が合わない。
        /// スクリーンショットを取り出しの条件で外さないのは、`mediaSubtypes` の条件の書き方を
        /// 実機で確かめていない（書き損じると起動のたびに落ちる）ため
        var skipped: [LibraryShot] = []
        /// 初めての読みの途中なら、**ここより古い写真はまだ読んでいない**。読み終えたら nil
        var frontier: Date?
        /// 初めての読みを終えたか
        var complete = false
        /// 読んだ中でいちばん新しい撮影日時（次はこれより新しい写真だけ読む）
        var newest: Date?
        /// 一冊の地名（鍵は旅の id）。**引けたら二度と引かない**
        var names: [String: String] = [:]
        /// 地名と一緒に分かった土地の時間帯（鍵は旅の id・`TimeZone.identifier`）
        var zones: [String: String] = [:]
        /// 地名を引けなかった時刻（鍵は旅の id）。`nameRetryAfter` の間は引き直さない
        var failedAt: [String: Date] = [:]
        /// 前に識別子で突き合わせた時刻（`maySweep`）。前の版の置き場には無い（nil で読める）
        var lastSweep: Date?
    }

    // MARK: - 読む段

    /// 次に読む所
    enum Step: Equatable {
        /// 何も覚えていない（新しい順に全部）
        case full
        /// 初めての読みの続き（`before` より古い写真）
        case resume(before: Date)
        /// 前回より新しい写真だけ
        case newer(after: Date)
    }

    static func firstStep(_ index: Index?) -> Step {
        guard let index, !(index.shots.isEmpty && index.frontier == nil && !index.complete) else { return .full }
        if !index.complete {
            // 途中の印が無いのに終わっていない（書いた直後に落ちた）——頭から読み直す
            guard let frontier = index.frontier else { return .full }
            return .resume(before: frontier)
        }
        guard let newest = index.newest else { return .full }
        return .newer(after: newest)
    }

    /// 識別子で突き合わせ直すか。**読み終えた後で、ライブラリの数と覚えている数が違うとき**
    /// （写真を消した・一部の許可を選び直した・`since` より古くなって落ちた）。
    /// 数は `maxShots` で頭打ちにして比べる（上限を超えるライブラリで毎回突き合わせない。
    /// その代わり、上限を超える人が消した写真は数が上限を割るまで残る——表紙が出ないだけ）
    static func needsSweep(_ index: Index, libraryCount: Int, since: Date) -> Bool {
        guard index.complete else { return false }
        let kept = index.shots.lazy.filter { $0.date >= since }.count
        let skipped = index.skipped.lazy.filter { $0.date >= since }.count
        return min(libraryCount, maxShots + skipped) != kept + skipped
    }

    /// 新しく読んだ写真を足す。**同じ識別子は新しく読んだ方**、`since` より古いものは落とし、
    /// 新しい順に並べて `maxShots` 枚まで（古い方を落とす）
    static func merged(_ old: [LibraryShot], adding new: [LibraryShot], since: Date,
                       limit: Int = maxShots) -> [LibraryShot] {
        var byId: [String: LibraryShot] = [:]
        byId.reserveCapacity(old.count + new.count)
        for shot in old { byId[shot.id] = shot }
        for shot in new { byId[shot.id] = shot }
        let kept = byId.values.filter { $0.date >= since }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id < $1.id }
        return Array(kept.prefix(limit))
    }

    /// 突き合わせ: 今ライブラリにある識別子（`current`）のうち、覚えている写真はそのまま使い
    /// （日時・位置を読み直さない）、知らない識別子だけを返す（呼び手が読む）。
    /// 覚えていてライブラリに無い写真は落ちる
    static func sweep(known: [LibraryShot], current: [String]) -> (kept: [LibraryShot], unknown: [String]) {
        var byId: [String: LibraryShot] = [:]
        byId.reserveCapacity(known.count)
        for shot in known { byId[shot.id] = shot }
        var kept: [LibraryShot] = []
        var unknown: [String] = []
        for id in current {
            if let shot = byId[id] { kept.append(shot) } else { unknown.append(id) }
        }
        return (kept, unknown)
    }

    // MARK: - 棚に出す一冊

    /// 棚に出す端末の一冊（新しい旅が先頭）。`trips` は `found(in:)` で探した旅
    /// （探すのは後ろの読みの中で1回。画面を描くたびに探し直さない）。
    ///
    /// - **人の棚には出さない**（`isMine` が偽なら空）
    /// - 覚えた土地の時間帯で日を切り直す（`LibraryTrips.recut`）
    /// - **投稿済みの日がある旅は出さない**（投稿した一冊と2冊に見える）
    static func books(_ trips: [LibraryTrip], posted: [LibraryTrips.PostedShot],
                      zones: [String: String], isMine: Bool) -> [LibraryTrip] {
        guard isMine else { return [] }
        return trips
            .map { trip in
                guard let id = zones[trip.id], let zone = TimeZone(identifier: id),
                      !(trip.zoneIsKnown && trip.timeZone.identifier == id) else { return trip }
                return LibraryTrips.recut(trip, timeZone: zone)
            }
            .filter { LibraryTrips.postedDays(trip: $0, posted: posted) == 0 }
    }

    /// 写真から旅を探す（`LibraryTrips.find` そのまま・家は推す）。新しい旅が先頭
    static func found(in shots: [LibraryShot]) -> [LibraryTrip] {
        LibraryTrips.find(shots)
    }

    /// 地名を引く一冊（新しい旅から `limit` 冊まで）。
    ///
    /// **初めての読みを終えてから**（`complete`）。読みの途中は家の推しや旅の始まりが動き、
    /// 旅の id（いちばん古い写真）が変わる——同じ旅の地名を何度も引くことになる。
    /// 位置の無い旅・引けた旅・引けなかったばかりの旅は引かない
    static func toLookUp(_ trips: [LibraryTrip], index: Index, now: Date, limit: Int = maxLookupsPerRun) -> [LibraryTrip] {
        guard index.complete else { return [] }
        return Array(trips.lazy.filter { trip in
            guard trip.center != nil, index.names[trip.id] == nil else { return false }
            guard let failed = index.failedAt[trip.id] else { return true }
            return now.timeIntervalSince(failed) >= nameRetryAfter
        }.prefix(limit))
    }

    /// 棚の題（地名が引けたら「金沢市の旅」、引けなければ期間）
    static func title(of trip: LibraryTrip, name: String?) -> String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return L("\(name)の旅", "Trip to \(name)")
        }
        return LibraryTrips.periodText(trip)
    }

    /// 端末の一冊は共有しない（上の「見える範囲」）
    static func canShare(_ trip: LibraryTrip) -> Bool { false }

    /// 「旅の写真から」の流れで、棚の一冊に当たる旅（同じ id、無ければ表紙の写真を含む旅）
    static func matching(_ book: LibraryTrip, in trips: [LibraryTrip]) -> LibraryTrip? {
        if let same = trips.first(where: { $0.id == book.id }) { return same }
        guard let anchor = book.cover?.id ?? book.shots.first?.id else { return nil }
        return trips.first { $0.shots.contains { $0.id == anchor } }
    }
}

// MARK: - 端末の置き場

/// 要約の置き場（Application Support の `DeviceTrips/index.json`）。**端末の中だけ**——
/// iCloud のバックアップにも入れない（写真の位置の控えなので）
enum DeviceTripIndexFile {

    static func defaultURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("DeviceTrips", isDirectory: true)
            .appendingPathComponent("index.json")
    }

    /// 読めない・版が違うときは nil（読み直す）
    static func load(from url: URL?) -> DeviceTrips.Index? {
        guard let url, let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode(DeviceTrips.Index.self, from: data),
              index.version == DeviceTrips.Index.currentVersion else { return nil }
        return index
    }

    static func save(_ index: DeviceTrips.Index, to url: URL?) {
        guard let url, let data = try? JSONEncoder().encode(index) else { return }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        #if canImport(Darwin)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var target = directory
        try? target.setResourceValues(values)
        #endif
    }

    /// 消す（サインアウト・退会）
    static func remove(at url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// 要約の1枚を短い鍵で書く（5万枚で 約5MB に収める）
extension LibraryShot: Codable {
    private enum CodingKeys: String, CodingKey { case i, t, a, o }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .i),
                  date: Date(timeIntervalSince1970: try c.decode(Double.self, forKey: .t)),
                  lat: try c.decodeIfPresent(Double.self, forKey: .a),
                  lng: try c.decodeIfPresent(Double.self, forKey: .o))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .i)
        try c.encode(date.timeIntervalSince1970.rounded(), forKey: .t)
        try c.encodeIfPresent(lat, forKey: .a)
        try c.encodeIfPresent(lng, forKey: .o)
    }
}
