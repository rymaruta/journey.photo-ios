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
///    （作る画面の「場所」と同じ決まり）。候補を解き直しても撮影地には触らない（`Place.resolve`）
///  - **座標は写真のまま送る（スポットの座標に置き換えない）。** 手で書いた撮影地がスポットを
///    指さないときは座標を送らない（2026-10-07 判断・`Place.coordsToSend`）。 `PlaceSpotSuggestions.coordsAfterPicking`
///    と同じ決まり。ストーリーを残すと `storyKeep.ts` が座標を写真のピンに写すので、置き換えると
///    最大十数 km ずれる。だから往復の確かめも**基準の写真の座標**で当てる（見る画面に届く座標）
///  - 探すのは撮影地の欄の候補と同じ仕組み（`PlaceSpotSuggestions`・3km 以内・公開済みだけ）
enum StorySpotSuggestion {

    /// 並べた写真の座標から、撮影地の候補を1つ（近い順）。基準は送る座標と同じ写真
    /// （`StoryQueue.baseCoords`）。GPS の写真が無い・近くに無い・見る画面で結べないなら nil
    static func spot(for coords: [Photo.Coords?], in spots: [OfficialSpot]) -> OfficialSpot? {
        guard let base = StoryQueue.baseCoords(coords) else { return nil }
        return PlaceSpotSuggestions.suggestions(query: "", near: base, index: spots)
            .first { candidate in
                // **見る画面で本当に結ばれるものだけ。** 見る画面に届く座標は基準の写真のもの
                // （`StoryQueue.coordsToSend`）なので、その座標と候補の名前で当てる
                StorySpotLink.spot(location: candidate.name, coords: base, in: spots)?.spotId
                    == candidate.spotId
            }
    }

    /// 作る画面の撮影地と候補。**撮影地が変わるのは本人が決めたとき（`pick`・欄の入力）だけ**
    struct Place: Equatable {
        /// 送る撮影地の文字（空＝付けない）
        var location = ""
        /// 写真の位置の近くの撮影スポット（解き直すのは `resolve` だけ）
        private(set) var suggestion: OfficialSpot?

        /// 写真か索引が変わったので候補を解き直す。**撮影地には触らない**（黙って付けない）
        mutating func resolve(coords: [Photo.Coords?], spots: [OfficialSpot]) {
            suggestion = StorySpotSuggestion.spot(for: coords, in: spots)
        }

        /// 写真の上に出す候補の札。撮影地を決めてあれば出さない
        var chip: OfficialSpot? { location.isEmpty ? suggestion : nil }

        /// 候補の札を押した
        mutating func pick() {
            guard let chip else { return }
            location = chip.name
        }

        /// 写真ごとに送る座標（並びは `coords` と同じ）。
        ///
        /// 2026-10-07 判断（投稿画面の `PendingPhoto.coordsToSend` と同じ決まり）: **撮影地の文字が
        /// 写真の近くのスポットを指すときだけ、写真の座標を送る。** 候補の札を押した・同じ名前を打った・
        /// 「高屋神社, 香川」と足した、は見る画面で結ばれる（`StorySpotLink`・5km 以内）ので、写真の座標の
        /// まま送る——撮影地からスポットへの導線は座標が無いと結べない。**それ以外の手で書いた地名**
        /// （自宅の町で撮って「東京」と書いた）に写真の位置を付けると、名前で伏せた場所がピン
        /// （残すと `storyKeep.ts` が写真の地図に写す）で分かってしまうので送らない。
        /// 撮影地が空の回は今までどおり（サーバーは撮影地の無い座標を保存しない・`stories.ts`）
        func coordsToSend(_ coords: [Photo.Coords?], spots: [OfficialSpot]) -> [Photo.Coords?] {
            let sent = StoryQueue.coordsToSend(coords)
            if location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return sent }
            guard PlaceCoordsRule.namesSpotNear(location, photo: StoryQueue.baseCoords(coords), spots: spots)
            else { return coords.map { _ in nil } }
            return sent
        }

        /// 送る前に撮影スポットの索引を待つか。撮影地があり、GPS の写真があり、索引がまだ無いとき
        /// （待たずに決めると、近くのスポットを指していても座標が落ちてスポットへの導線が消える）
        func needsSpotIndex(_ coords: [Photo.Coords?], spots: [OfficialSpot]) -> Bool {
            spots.isEmpty && !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && StoryQueue.baseCoords(coords) != nil
        }
    }
}
