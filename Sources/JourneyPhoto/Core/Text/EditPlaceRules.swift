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

    /// 保存で `coords: null` を送るか。**本人が撮影地を消した・書き換えたとき**（候補を選んだ回は除く）。
    /// 開いたときから撮影地が空で座標だけある写真（圏外で投稿した等）は、
    /// 題を直しただけで座標を消さない
    ///
    /// 2026-10-07 判断: **書き換えたときも消す。** 自宅の町の地名を「東京」に直しても、
    /// 写真の位置のピンが自宅のあたりに残っていた（投稿画面の `PendingPhoto.coordsToSend` と同じ考え）。
    /// 候補から選び直せば、その座標を送る（`pickedCoords`）
    static func clearsCoords(openedLocation: String?, currentLocation: String,
                             pickedCoords: Bool) -> Bool {
        !pickedCoords && changedByUser(openedLocation: openedLocation, currentLocation: currentLocation)
    }

    /// 差し替えで新しい写真の位置を書くか。**元からピンがあった写真だけ**、
    /// ピンを新しい写真の位置へ動かす。ピンの無い写真（Web の「地図に出さない」で
    /// 外した・撮影地も無い）に位置を戻さない。この画面で撮影地を消した・書き換えたときも
    /// 書かない（2026-10-07 判断・`clearsCoords` と同じ）
    static func keepsCoordsOnReplace(openedLocation: String?, openedHasCoords: Bool,
                                     currentLocation: String) -> Bool {
        openedHasCoords && !changedByUser(openedLocation: openedLocation, currentLocation: currentLocation)
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
