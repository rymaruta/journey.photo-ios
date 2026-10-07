import Foundation

/// 撮影地と一緒に**写真の座標（GPS 由来・約1km）を送るか**の、投稿・編集・ストーリーで共通の決まり
/// （2026-10-07 判断・owner から任された判断）。
///
/// 写真の座標を送るのは次のどれかのときだけ:
///  - (a) 撮影地が空（自動入力が間に合わなかった。空にした操作は各画面が別に止める）
///  - (b) 写真の位置から自動で入れた地名を一字も変えていない
///  - (c) 撮影地の文字が、写真から `photoKm` 以内の撮影スポットを指す（`StorySpotLink` で結ばれる）
///
/// それ以外（自宅の町で撮って「東京」と書いた）は写真の座標を送らない——場所を伏せたくて
/// 書き換えた人の意図に反して、ピンが撮った位置に立っていた。スポットを選んだ回は、写真が
/// スポットの近くなら写真の座標、遠ければ**スポットの座標**（`coordsForPickedSpot`）
enum PlaceCoordsRule {

    /// 写真の座標をスポットの名前に付けてよい距離（km）。見る画面がスポットへ結ぶ距離と同じ
    static let photoKm = StorySpotLink.maxKm

    /// 索引を待つ長さ。**控え（`OfficialSpotService` の端末の控え）があればすぐ返る**。
    /// 圏外で返ってこないときに、送るのを長く止めない
    static let indexWait: Duration = .seconds(2)

    /// (c) 撮影地の文字が、写真の近くの撮影スポットを指すか
    static func namesSpotNear(_ location: String, photo: Photo.Coords?, spots: [OfficialSpot]) -> Bool {
        let text = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let photo else { return false }
        return StorySpotLink.spot(location: text, coords: photo, in: spots) != nil
    }

    /// スポットを選んだ回に送る座標。**写真がスポットの `photoKm` 以内なら写真の座標**（撮った位置を
    /// スポットの丸めた座標で置き換えない）、遠い・位置の無い写真ならスポットの座標。
    /// **スポットに座標が無ければ nil**——写真の座標へは倒さない（名前と撮った位置が食い違う）
    static func coordsForPickedSpot(_ spotCoords: Photo.Coords?, photo: Photo.Coords?) -> Photo.Coords? {
        guard let spotCoords else { return nil }
        guard let photo, TravelDistance.kilometers(from: photo, to: spotCoords) <= photoKm else { return spotCoords }
        return photo
    }

    /// 決めるのに索引が要るのに、まだ手元に無い（`current` が空）ときだけ読む。
    /// `indexWait` を過ぎたら空のまま返す（(c) は当たらない＝写真の座標を送らない側に倒れる）
    static func index(current: [OfficialSpot], needed: Bool, wait: Duration = indexWait,
                      fetch: @escaping @Sendable () async -> [OfficialSpot]?) async -> [OfficialSpot] {
        guard needed, current.isEmpty else { return current }
        let found = await withTaskGroup(of: [OfficialSpot]?.self) { group -> [OfficialSpot]? in
            group.addTask { await fetch() }
            group.addTask {
                try? await Task.sleep(for: wait)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        return found ?? current
    }
}
