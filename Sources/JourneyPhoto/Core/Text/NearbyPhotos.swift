import Foundation

/// 「現在地・周辺の写真」（モック3-7）。
///
/// **測るのは、いま手元にある座標だけ。** 通信しない。
///
/// ⚠️ **座標は保存時に約1km（小数第2位）へ丸めてある**
/// （`api-user/src/sanitize.ts` の `sanitizeCoords`）。だから
/// 距離も約1kmの粗さしか無い——**「500m以内」とは言えない**。
/// モックの「500m以内・8件」をそのまま出すと、丸めで消えた精度を
/// 持っているふりになる。出すのは**「約Nkm以内」**と、数えた件数。
enum NearbyPhotos {

    /// 選べる半径（km）。**1km 未満を置かない**——丸めより細かい線は引けない
    static let radiusChoices: [Double] = [5, 10, 50]
    static let defaultRadius: Double = 5

    /// 近い順。**座標の無い写真は入らない**（距離を測りようが無い）
    static func photos(_ photos: [Photo], near center: Photo.Coords,
                       withinKm radius: Double) -> [(photo: Photo, km: Double)] {
        photos.compactMap { photo -> (Photo, Double)? in
            guard let coords = photo.coords else { return nil }
            let km = TravelDistance.kilometers(from: center, to: coords)
            guard km <= radius else { return nil }
            return (photo, km)
        }
        .sorted { $0.1 < $1.1 }
        .map { (photo: $0.0, km: $0.1) }
    }

    /// 写真の詳細の「この近くで撮られた写真」（板 02）。
    ///
    /// **その写真の座標から測る。** 座標の無い写真には節ごと出さない
    /// （空の配列を返す）——撮影地の文字が同じでも、座標の無い写真は
    /// 「近い」と言えない。
    ///
    /// **自分と、上の写真で送れる束は入れない**——ここに並べると同じ写真が
    /// 二度出る。上の束は開いた一覧（`context`）の中の兄弟だけ
    /// （`PhotoDetailView.heroGroup`）なので、**同じ式で数えて、実際に
    /// 上に出ている写真だけ**を落とす。
    ///
    /// 以前は全公開写真から `groupId` の文字だけで兄弟を落としていたので、
    /// (1) 一覧に居ない兄弟が上にも下にも出ず、(2) 持ち主の違う写真が
    /// 同じ `groupId` だと巻き添えで消えていた。束の判定は
    /// `PhotoGroups.groupKey`（空白を除いた `groupId` ＋持ち主）に任せる
    static func around(_ photo: Photo, in all: [Photo], context: [Photo] = [],
                       withinKm radius: Double = defaultRadius, limit: Int = 12) -> [Photo] {
        guard let center = photo.coords else { return [] }
        var seen = Set(PhotoGroups.siblings(of: photo, in: context).map(\.id))
        seen.insert(photo.id)
        var picked: [Photo] = []
        for (item, _) in photos(all, near: center, withinKm: radius) {
            guard seen.insert(item.id).inserted else { continue }
            picked.append(item)
            if picked.count >= limit { break }
        }
        return picked
    }

    /// 「地図で見る」（`NearbyMapScreen`）のピンから開いた写真に、個別ページが
    /// 在るとみなすか（`PhotoDetailView.fromPublicFeed`）。
    ///
    /// **呼び元の値は開いた1枚にだけ効かせる。** 近くの写真は公開一覧
    /// （`around` に渡す `fetchPhotos`）から来たので `true`。以前は開いた
    /// 1枚の値を全ピンに渡していて、マイページの下書きから開くと、近くの
    /// 他人の公開写真まで共有がトップ（`/?photo=`）に落ちていた
    static func fromPublicFeed(_ photo: Photo, openedId: String, openedFromPublicFeed: Bool) -> Bool {
        photo.id == openedId ? openedFromPublicFeed : true
    }

    /// 現在地のまわり（選べる**最大**の半径）に、撮影地の分かる写真が1枚も無いか。
    ///
    /// 地図は開くと現在地へ寄るので、写真の無い土地にいる人には**ピンが1本も無い
    /// 地図**が出ていた（「アプリ再起動したら現在地になる」の答えの続き）。
    /// これが真のとき、地図は「近くに写真はありません · 全体を見る」を出す。
    /// **撮影地の分かる写真が0枚なら偽**——そのときは別の帯（「撮影地の分かる写真が
    /// ありません」）が答えで、「全体」も無い
    static func noneNearby(_ photos: [Photo], here: Photo.Coords) -> Bool {
        let located = photos.filter { $0.coords != nil }
        guard !located.isEmpty else { return false }
        return self.photos(located, near: here, withinKm: radiusChoices.max() ?? defaultRadius).isEmpty
    }

    /// 「近くに写真はありません · 全体を見る」の帯を**下げたか**。
    ///
    /// 判定（`noneNearby`）は利用者の現在地しか見ないので、以前は**指で地図を
    /// 動かしてピンを見ている間も**「近くに写真はありません」が出続けていた。
    /// 下げるのは利用者が自分で動かしたときだけ——こちらが寄せた回（現在地を
    /// 追う・写真全体へ寄せる・拡大縮小のボタン）でも地図の移動は届くので、
    /// そこで下げると現在地に寄せた直後に帯が消える。
    ///
    ///     現在地が取れた           → 出す（取り直したら、また出す）
    ///     「全体を見る」を押した    → 下げる
    ///     利用者が地図を動かした    → 下げる
    ///     こちらが地図を動かした    → そのまま
    struct NoneNearbyBanner: Equatable {
        private(set) var dismissed = false

        mutating func located() { dismissed = false }
        mutating func showedAll() { dismissed = true }
        mutating func cameraMoved(byUser: Bool) {
            if byUser { dismissed = true }
        }
    }

    /// 距離の言い方。**必ず「約」を付ける**（丸めた座標から出した値なので）。
    ///
    /// 1km 未満は「1km以内」——「0.3km」と書くと、持っていない精度を
    /// 言うことになる。
    static func label(km: Double) -> String {
        if km < 1 { return L("1km以内", "within 1 km") }
        if km < 10 { return L("約\(String(format: "%.1f", km))km", "about \(String(format: "%.1f", km)) km") }
        return L("約\(Int(km.rounded()))km", "about \(Int(km.rounded())) km")
    }

    /// 見出し。**数えた件数だけ**を出す
    static func heading(radiusKm: Double, count: Int) -> String {
        let r = radiusKm < 10 ? String(format: "%.0f", radiusKm) : String(Int(radiusKm))
        return L("半径約\(r)kmの写真 \(count)枚", "\(count) photos within about \(r) km")
    }
}
