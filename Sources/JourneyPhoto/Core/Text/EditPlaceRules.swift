import Foundation

/// 写真の編集で、座標を**消すか**・差し替えで**書くか**の決まり。
///
/// **保存済みの値ではなく、この画面での操作で決める。** 判定を画面の外に
/// 置くのは、Linux の模型では画面を動かせず試験できないため。
enum EditPlaceRules {

    /// 撮影地の文字を、開いたときから変えたか（前後の空白は見ない）。空にした回も含む
    static func changedByUser(openedLocation: String?, currentLocation: String) -> Bool {
        trim(openedLocation ?? "") != trim(currentLocation)
    }

    /// 保存で `coords: null` を送るか（決まりは投稿・ストーリーと同じ `PlaceCoordsRule`・2026-10-07 判断）。
    ///
    /// 写真の座標を残すのは、撮影地を**変えていない**（開いたときから空の写真も、題を直しただけなら
    /// 残す）か、変えた撮影地が**写真の近くの撮影スポットを指す**（「高屋神社」に「, 香川」を足した）
    /// ときだけ。**消した・それ以外に書き換えたときは消す**——自宅の町の地名を「東京」に直しても、
    /// 写真の位置のピンが自宅のあたりに残っていた。候補から選び直した回は、その座標を送るので消さない
    ///
    /// - Parameters:
    ///   - photoCoords: 写真のいまの座標（(c) を見る）
    ///   - spots: 撮影スポットの索引。空なら (c) は当たらない（消す側に倒れる）。
    ///     🔴 **nil は「索引を読めなかった（時間切れ・圏外）」**——書き換えた撮影地がスポットを指すか
    ///     分からないので**消さない**（分からないまま消すと、サーバーのピンが黙って消える・2026-10-09 のレビュー）。
    ///     撮影地を空にした回は索引が要らないので、nil でも消す
    static func clearsCoords(openedLocation: String?, currentLocation: String, pickedCoords: Bool,
                             photoCoords: Photo.Coords? = nil, spots: [OfficialSpot]? = []) -> Bool {
        guard !pickedCoords, changedByUser(openedLocation: openedLocation, currentLocation: currentLocation)
        else { return false }
        guard let spots else { return trim(currentLocation).isEmpty }
        return !PlaceCoordsRule.namesSpotNear(currentLocation, photo: photoCoords, spots: spots)
    }

    /// 索引が無いと `clearsCoords` を決められないか（保存の前に索引を待つかどうか）
    static func needsSpotIndex(openedLocation: String?, currentLocation: String, pickedCoords: Bool,
                               photoCoords: Photo.Coords?) -> Bool {
        !pickedCoords && photoCoords != nil && !trim(currentLocation).isEmpty
            && changedByUser(openedLocation: openedLocation, currentLocation: currentLocation)
    }

    /// 差し替えで新しい写真の位置を書くか。**元からピンがあった写真だけ**、
    /// ピンを新しい写真の位置へ動かす。ピンの無い写真（Web の「地図に出さない」で
    /// 外した・撮影地も無い）に位置を戻さない。この画面で撮影地を消した・書き換えたときも
    /// 書かない——ただし書き換えた撮影地が新しい写真の近くのスポットを指すなら書く
    /// （`clearsCoords` と同じ決まり・2026-10-07 判断）
    ///
    /// 🔴 **`spots` が nil（索引を読めなかった）なら、撮影地を空にした回のほかはピンを残す**
    /// （`clearsCoords` と同じ理由。分からないことを「落とす」にしない）
    static func keepsCoordsOnReplace(openedLocation: String?, openedHasCoords: Bool, currentLocation: String,
                                     newPhotoCoords: Photo.Coords? = nil, spots: [OfficialSpot]? = []) -> Bool {
        guard openedHasCoords else { return false }
        guard changedByUser(openedLocation: openedLocation, currentLocation: currentLocation) else { return true }
        guard let spots else { return !trim(currentLocation).isEmpty }
        return PlaceCoordsRule.namesSpotNear(currentLocation, photo: newPhotoCoords, spots: spots)
    }

    private static func trim(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 写真の編集で、公開（`published`）と公開範囲（`audience`）を**送るか**の決まり。
///
/// 🔴 **変えたときだけ送る**（ほかの項目と同じ）。開いた値を毎回送っていたので、
/// 公開一覧の古い写し（建て直しまで古い）から開いて題だけ直すと、別の画面で
/// 絞った公開範囲や非公開が**黙って全体公開に戻った**。
///
/// 🔴 **非公開にするときは公開範囲を送らない。** 空（全体）を送っていたので、
/// 「フォロワーのみ」の写真を非公開にすると範囲が消え、公開に戻すと全体に
/// 公開されていた。送らなければサーバーは範囲を残す（`photoUpdate.ts`）
enum EditVisibilityRules {
    /// - Parameters:
    ///   - openedAudience: 開いたときの範囲。**知らない値なら nil**（送らない＝広げも狭めもしない）
    static func patch(openedPublished: Bool, openedAudience: Audience?,
                      published: Bool, audience: Audience) -> (published: Bool?, audience: String?) {
        let sendPublished: Bool? = published != openedPublished ? published : nil
        guard let openedAudience, published, audience != openedAudience else {
            return (sendPublished, nil)
        }
        return (sendPublished, audience.patchValue)
    }
}
