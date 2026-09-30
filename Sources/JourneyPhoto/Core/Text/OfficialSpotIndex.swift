import Foundation

/// 撮影スポットの索引（`OfficialSpot`）を**手元で引く**。通信しない。
///
/// 名前で探す（地図の検索窓）と、近くのスポット（画面の末尾）の2つ。
/// どちらも画面を持たない層に置いて、Linux の `swift test` で動かす。
enum OfficialSpotIndex {

    /// 名前・読み・英語名・別名・国・都道府県・市区町村のどれかに当たるもの。
    /// **空の語は何も当てない**（「絞っていない」）。全角半角・大小は区別しない。
    ///
    /// **名前で当たったものが先**、別名で当たったものが次、地域だけで当たったものはその後ろ。
    /// 同じ段の中は slug 順（毎回同じ並びにする）。`limit` が nil なら全部
    /// （地図は枠で並べ直してから切るので、ここでは切らない）。
    /// `aliases` は slug → 別名（`OfficialSpotService.fetchAliases`・無ければ空）
    static func matches(_ spots: [OfficialSpot], query: String, limit: Int? = nil,
                        aliases: [String: [String]] = [:]) -> [OfficialSpot] {
        let needle = MapSearch.fold(query)
        guard !needle.isEmpty else { return [] }
        let ranked = spots
            .compactMap { spot -> (OfficialSpot, Int)? in
                if nameMatches(spot, needle: needle) { return (spot, 0) }
                if aliasMatches(aliases[spot.slug], needle: needle) { return (spot, 1) }
                if regionMatches(spot, needle: needle) { return (spot, 2) }
                return nil
            }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.slug < $1.0.slug }
            .map(\.0)
        guard let limit else { return ranked }
        return Array(ranked.prefix(limit))
    }

    private static func nameMatches(_ spot: OfficialSpot, needle: String) -> Bool {
        [spot.name, spot.reading, spot.nameEn]
            .compactMap { $0 }
            .contains { MapSearch.fold($0).contains(needle) }
    }

    static func aliasMatches(_ aliases: [String]?, needle: String) -> Bool {
        (aliases ?? []).contains { MapSearch.fold($0).contains(needle) }
    }

    private static func regionMatches(_ spot: OfficialSpot, needle: String) -> Bool {
        // 国は日本の外の行だけに載る（Web の「さがす」も国で当てる・`lib/data/spotSearchFeed.ts`）
        [spot.region?.country, spot.region?.prefecture, spot.region?.city]
            .compactMap { $0 }
            .contains { MapSearch.fold($0).contains(needle) }
    }

    /// 「近く」と呼んでよい距離（km）。写真から作る撮影地（`DerivedSpot.nearbyMaxKm`）と同じ
    static let nearbyMaxKm: Double = 50

    /// 近くの撮影スポット。**座標を持っているものだけ**、自分を除いて近い順。
    /// 距離は写真と同じ式（`TravelDistance.kilometers`）。同じ距離は slug 順。
    /// **同じ `spotId` は1つだけ（先勝ち）**——画面は `spotId` で並べるので、
    /// 重なると同じ札が2つ出る（索引を読む側 `LenientOfficialSpotList` でも落とす）
    ///
    /// 🔴 **`nearbyMaxKm` より遠い場所は出さない。** 以前は上限が無く、近くに
    /// 索引の行が少ない場所では数百km先まで「近く」と名乗っていた。
    /// 足りなくても遠い場所で埋めない（0件なら節ごと出ない）
    static func nearby(_ spot: OfficialSpot, in spots: [OfficialSpot],
                       limit: Int = 6, maxKm: Double = nearbyMaxKm) -> [(spot: OfficialSpot, km: Double)] {
        guard let here = spot.coords else { return [] }
        var seen: Set<String> = [spot.spotId]
        return spots
            .filter { seen.insert($0.spotId).inserted }
            .compactMap { other -> (spot: OfficialSpot, km: Double)? in
                guard let there = other.coords else { return nil }
                let km = TravelDistance.kilometers(from: here, to: there)
                return km <= maxKm ? (other, km) : nil
            }
            .sorted { $0.km != $1.km ? $0.km < $1.km : $0.spot.slug < $1.spot.slug }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - 経路の行き先

    /// 経路の行き先を名前の検索結果から拾い直すときの距離（km）。
    ///
    /// 🔴 **索引の座標は約1km に丸めてある**（小数2桁。台帳 `content/spots.json`
    /// の時点で丸めてあり、丸める前の値はどこにも無い）。丸めのずれは最大で
    /// 緯度 0.005°≒0.56km・経度 0.005°≒0.45km、斜めで約0.7km。そのまま
    /// 経路に渡すと、山や滝では**入口と違う道の上**に案内する。
    /// 地図で押した地点の拾い直し（`PlaceLookup.sameSpotKm` = 0.3km）より
    /// 広く取るのはこのずれのぶん
    static let directionsMatchKm: Double = 1.5

    /// 名前で探した候補のうち、丸めた座標から `directionsMatchKm` 以内で
    /// いちばん近いものの位置。無ければ nil（丸めた座標に名前を付けて渡す）
    static func directionsTargetIndex(of candidates: [Photo.Coords], near rounded: Photo.Coords) -> Int? {
        PlaceLookup.nearestIndex(of: candidates, to: rounded, withinKm: directionsMatchKm)
    }

    /// 経路の検索を待つ秒数。過ぎたら丸めた座標にスポット名を付けて開く
    static let directionsTimeout: Double = 3

    /// `operation` の答えを `seconds` 秒だけ待つ。過ぎたら nil を返し、`operation` は止める。
    ///
    /// **`operation` が止まるのを待たない。** 子タスクの組（`withTaskGroup`）で競わせると、
    /// 抜けるときに全部の子の終わりを待つので、取り消しに応じない処理（地図の検索）
    /// では時間切れが効かない。呼んだ側が取り消されたときも、すぐ nil を返す
    static func firstWithin<T>(seconds: Double, _ operation: @escaping () async -> T?) async -> T? {
        let gate = FirstResultGate<T>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
                gate.start(continuation)
                let work = Task {
                    gate.finish(await operation())
                }
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                    work.cancel()
                    gate.finish(nil)
                }
                gate.onCancel = { work.cancel() }
            }
        } onCancel: {
            gate.cancel()
        }
    }
}

/// `firstWithin` の「先に来た1回だけ返す」門
private final class FirstResultGate<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?
    private var done = false
    private var cancelled = false
    var onCancel: (() -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onCancel }
        set {
            lock.lock()
            let fire = cancelled
            _onCancel = newValue
            lock.unlock()
            if fire { newValue?() }
        }
    }
    private var _onCancel: (() -> Void)?

    func start(_ c: CheckedContinuation<T?, Never>) {
        lock.lock()
        if cancelled || done { done = true; lock.unlock(); c.resume(returning: nil); return }
        continuation = c
        lock.unlock()
    }

    func finish(_ value: T?) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        done = true
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: value)
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let hook = _onCancel
        lock.unlock()
        hook?()
        finish(nil)
    }
}
