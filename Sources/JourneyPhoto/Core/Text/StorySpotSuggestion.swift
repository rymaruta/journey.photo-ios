import Foundation

/// ストーリーを作るときの**撮影地の候補**（戦略の計画8「ストーリーに撮影地を付けて撮影地ページへつなぐ」）。
///
/// 写真の位置（EXIF の GPS を約1kmに丸めたもの・`ImagePreparer.readCoords`）の近くに公開済みの
/// 撮影スポットがあれば、その名前を写真の上に候補として出す。押すと撮影地に入り、見る画面では
/// 撮影地の行が撮影スポットのガイドへつながる（`StorySpotLink`）。
///
/// 2026-10-03 判断:
///  - **サーバーは変えない。** ストーリーの行に `spotId` を持たせる口は無い（`stories.ts` の
///    `createStory` は `location` と `coords` だけ受ける）。撮影地の文字をスポットの名前そのものに
///    するだけで、見る画面の `StorySpotLink` が結べる。結べない候補は出さない（下の往復の確かめ）
///  - **自動では付けない・押したときだけ。** ストーリーは「いま」の投稿なので、撮影地を黙って
///    付けると居場所を知らせることになる。これまでどおり、撮影地を送るのは本人が決めたときだけ
///    （作る画面の「場所」と同じ決まり）
///  - **候補から付けた回は、写真の座標でなくスポットの座標を送る。** 見る人に出る位置を
///    「撮影地の単位」（公開済みのスポットの位置）にし、本人の居た約1kmの升目を出さない。
///    見る画面の距離の判定も 0km になり、確実に結ばれる
///  - 探すのは撮影地の欄の候補と同じ仕組み（`PlaceSpotSuggestions`・3km 以内・公開済みだけ）
enum StorySpotSuggestion {

    /// 並べた写真の座標から、撮影地の候補を1つ（近い順）。基準は送る座標と同じ写真
    /// （`StoryQueue.baseCoords`）。GPS の写真が無い・近くに無い・見る画面で結べないなら nil
    static func spot(for coords: [Photo.Coords?], in spots: [OfficialSpot]) -> OfficialSpot? {
        guard let base = StoryQueue.baseCoords(coords) else { return nil }
        return PlaceSpotSuggestions.suggestions(query: "", near: base, index: spots)
            .first { candidate in
                // **見る画面で本当に結ばれるものだけ。** スポットの名前が市町村名と同じなどで
                // 結ばれない候補を出すと、付けても押せる札にならない
                StorySpotLink.spot(location: candidate.name, coords: candidate.coords, in: spots)?.spotId
                    == candidate.spotId
            }
    }

    /// 写真ごとに送る座標。撮影地が候補のスポットの名前そのものなら、**GPS のある写真は
    /// スポットの座標に置き換える**（撮影地の単位だけを出す）。GPS の無い写真・基準から遠い写真は
    /// これまでどおり送らない（`StoryQueue.coordsToSend`）。それ以外の撮影地は写真の座標のまま
    static func coordsToSend(_ coords: [Photo.Coords?], location: String,
                             suggested: OfficialSpot?) -> [Photo.Coords?] {
        let sent = StoryQueue.coordsToSend(coords)
        guard let suggested, let spotCoords = suggested.coords,
              location.trimmingCharacters(in: .whitespacesAndNewlines) == suggested.name else { return sent }
        return sent.map { $0 == nil ? nil : spotCoords }
    }
}
