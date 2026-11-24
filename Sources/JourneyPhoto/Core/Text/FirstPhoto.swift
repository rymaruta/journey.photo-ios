import Foundation

/// **この場所の、最初の1枚をお願いする**（札 #710 の案7・2026-11-23 owner 承認）。
///
/// 写真の無い観光スポットで、「お願いする」温度の言い方にそろえる。言葉は案の頁のとおり。
/// 「急いで」「今だけ」「誰より先に」のような急かす言葉・競わせる言葉は使わない。
///
/// 2026-11-23 判断: 「最初の1枚」と言うのは、**端末で写真の数が0と読めているときだけ**（`announces`）。
/// 読めていないとき（一覧を取れなかった・まだ読んでいる）は言わない——言いすぎるより言わない方へ倒す
///
/// 2026-11-23 判断: 案の頁の文は「この場所の最初の写真」「この場所を探す人」だったが、「この場所」は使わないと決めた呼び名
/// （CLAUDE.md の呼び名の決まり・`PlaceTermWordingTests`）なので、決まりの呼び名「この観光スポット」に替えた
enum FirstPhoto {

    /// 写真の無い場所の見出し
    static var emptyTitle: String { L("まだ写真がありません", "No photos yet") }
    /// 本文
    static var emptyMessage: String {
        L("あなたの1枚が、この観光スポットの最初の写真になります", "Your photo will be the first one here")
    }
    /// ボタン
    static var postLabel: String { L("最初の1枚を投稿する", "Post the first photo") }
    /// 投稿したあとの知らせの1行目「宝厳院の最初の1枚になりました」
    static func postedTitle(_ name: String) -> String {
        L("\(name)の最初の1枚になりました", "You posted the first photo of \(name)")
    }
    /// 知らせの2行目（お礼と、投稿が誰の役に立つか）
    static var postedDetail: String {
        L("ありがとうございます。この観光スポットを探す人の、最初の手がかりになります",
          "Thank you. It's the first clue for people looking for this place.")
    }

    /// 「最初の1枚」と言ってよいか。**写真の数を読めていて、0のときだけ**
    static func announces(photosKnown: Bool, count: Int) -> Bool {
        photosKnown && count == 0
    }

    /// その観光スポットに結ばれた写真の数（端末で読めている一覧から。自動の結びも数える・観光スポットの頁の `linked` と同じ）
    static func count(spotId: String, in photos: [Photo], links: SpotPhotoLinks) -> Int {
        SpotPhotoLinks.photos(photos, linkedTo: spotId, links: links).count
    }
}
