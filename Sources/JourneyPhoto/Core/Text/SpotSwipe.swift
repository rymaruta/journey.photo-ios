import Foundation

/// 撮影スポットを払う（2026-11-11 owner の要望「撮影スポットを払う」の①・設計は案の資料の第7章）。
///
/// ホームの上の札の**1枚目**に入口を置き、押すと全画面の払う画面（`SpotSwipeView`・中身は
/// 旅行プランの作る流れと同じ `TripPickerView`）が開く。**未ログインでも払える**——払った「行きたい」は
/// 今の `WishlistStore`（未ログインは端末の共有の鍵・ログインした回にその人へ引き継ぐ）に入る。
///
/// 結果（行きたい場所の地図・旅行プラン）はログインしないと見えない。5枚払って「行きたい」が1つ以上に
/// なったら、札の山の中に**ログインを案内する札を1枚だけ挟む**（窓で止めない・左へ払えば続く・次は10枚あと）。
/// 札 #432（2026-10-31 owner「登録なしで保存はやめる」）と食い違わないよう、未ログインの人には一覧を見せない。
///
/// ここは画面を持たない計算だけ（挟む札を出すか・入口の札の文・札の写真）。Linux で試験する。
enum SpotSwipe {

    /// 最初に挟む札を出すまでに払う枚数
    static let firstPause = 5
    /// 挟んだ札を払ってから、次に出すまでの枚数
    static let pauseEvery = 10

    /// 挟む札を出すか。
    ///
    /// - Parameters:
    ///   - decisions: この回に払った枚数（`TripPickerModel.decisions.count`）
    ///   - wants: この回に「行きたい」にした数（`TripPickerModel.picked.count`）
    ///   - continuedAt: 挟んだ札を払って続けたときの枚数（まだなら nil）
    /// - Returns: 「行きたい」が1つ以上で、初回は `firstPause` 枚、2回目からは続けてから `pauseEvery` 枚払ったとき
    static func showsPause(decisions: Int, wants: Int, continuedAt: Int?) -> Bool {
        guard wants > 0 else { return false }
        guard let continuedAt else { return decisions >= firstPause }
        return decisions >= continuedAt + pauseEvery
    }

    // MARK: - 入口の札（ホーム）

    /// 入口の札の題。**札の幅で1行に収まる長さ**（札の題は1行・#417 ③。2026-11-11 Web の 390 幅で
    /// 「写真を払って、…」と切れたのを見て短くした）。払うことは眉（`eyebrowLabel`）で言う
    static var cardTitle: String { L("行きたい場所を探す", "Find where to go") }
    /// 入口の札の眉の読み上げ（字は英字の眉「WHERE TO NEXT」）
    static var eyebrowLabel: String { L("写真を払う", "Swipe photos") }

    /// 入口の札の一行。**2回目からは「行きたい n か所 · 続きから」**（1回目は払い方と、ログインが要らないこと）
    ///
    /// - Parameters:
    ///   - started: 一度でも払う画面を開いたか（`SpotSwipeProgress.started`）
    ///   - wishCount: 「行きたい」の数（`WishlistStore.spotIds.count`）
    ///   - signedIn: ログイン中か
    static func cardLine(started: Bool, wishCount: Int, signedIn: Bool) -> String {
        if started {
            return L("行きたい \(wishCount) か所\u{2002}続きから",
                     wishCount == 1 ? "1 place saved\u{2002}Continue" : "\(wishCount) places saved\u{2002}Continue")
        }
        return signedIn
            ? L("右へ払うと行きたい", "Swipe right to save")
            : L("ログインなしではじめる", "No sign-in needed")
    }

    /// 入口の札の左の写真に使う撮影スポット。**写真を出せる公開済み**（`TripPicker.isEligible`）で、
    /// ほかの札に出ているものを除き、日替わりで1件（同じ日なら同じ札・開くたびに替わらない）
    static func cover(spots: [OfficialSpot], excluding ids: Set<String>, day: Int) -> OfficialSpot? {
        CoverPool(spots: spots).cover(spots: spots, excluding: ids, day: day)
    }

    /// 入口の札の写真の候補の並び（写真を出せる場所の**位置**を `spotId` の順に）。**索引が変わったときだけ作る**。
    ///
    /// 2026-11-14 判断（札 #594・Mac run 1238 の数）: 前は札の body を評価するたびに、索引（本番 約 3,900 件）を
    /// 絞って `spotId` で並べ替えていた。`home.topCard.choices` が 70 回で合計 8.3 秒（1 回 約 120〜140ms）、
    /// その最中の積みの見本は 11 件すべて `SpotSwipe.cover` の並べ替え・写しだった。並びは索引だけで決まるので、
    /// 索引が変わったとき 1 回だけ作り（`HomeTopCardView` の `HomeTopCardMemo`）、毎回は除く場所を飛ばして数えるだけにする。
    /// 選ぶ 1 件は前と同じ（同じ `spotId` が並ぶときも元の順を保つ）
    struct CoverPool {
        /// 写真を出せる場所の、元の索引の中の位置（`spotId` の順・同じ `spotId` は元の順）
        let indices: [Int]
        /// 同じ順の `spotId`
        let ids: [String]
        /// 作ったときの索引の件数（違う索引を渡されたと気づくため）
        let spotCount: Int

        init(spots: [OfficialSpot]) {
            let eligible = spots.indices.filter { TripPicker.isEligible(spots[$0]) }
            let sorted = eligible.sorted { lhs, rhs in
                let a = spots[lhs].spotId, b = spots[rhs].spotId
                return a != b ? a < b : lhs < rhs
            }
            indices = sorted
            ids = sorted.map { spots[$0].spotId }
            spotCount = spots.count
        }

        /// `spots` は作ったときと同じ索引を渡す。除く場所を飛ばして、日替わりの 1 件。
        ///
        /// 2026-11-14 判断（札 #594 の確かめ役）: 索引を書き換えて `spotsRevision` を進め忘れると、古い位置で
        /// 引いて範囲外で落ちる。件数が違う・選んだ位置の `spotId` が違うときは、その場で作り直して選ぶ（落ちない・選ぶ 1 件は正しい）
        func cover(spots: [OfficialSpot], excluding excluded: Set<String>, day: Int) -> OfficialSpot? {
            guard spots.count == spotCount else {
                return CoverPool(spots: spots).cover(spots: spots, excluding: excluded, day: day)
            }
            let count = excluded.isEmpty ? ids.count : ids.reduce(0) { $0 + (excluded.contains($1) ? 0 : 1) }
            guard count > 0 else { return nil }
            var remaining = ((day % count) + count) % count
            for (position, id) in ids.enumerated() where !excluded.contains(id) {
                if remaining == 0 {
                    let spot = spots[indices[position]]
                    guard spot.spotId == id else {
                        return CoverPool(spots: spots).cover(spots: spots, excluding: excluded, day: day)
                    }
                    return spot
                }
                remaining -= 1
            }
            return nil
        }
    }

    // MARK: - 挟む札・足元

    /// 挟む札の題（何が見られるかで言う）。
    /// 2026-11-14 判断（前回の点検の残り）: **「を」の後で改行し、文を「見る」で閉じる。** 前は明朝 22 の1文が
    /// 「…旅行プラン」で折り返し、2行目が「で」1字だけになっていた（2026-11-13 の画面写真）
    static func pauseTitle(wants: Int) -> String {
        L("選んだ \(wants) か所を\n地図と旅行プランで見る",
          wants == 1 ? "See your 1 place on a map and in a trip" : "See your \(wants) places on a map and in a trip")
    }

    /// 挟む札の説明（1行）
    static func pauseLine(signedIn: Bool) -> String {
        signedIn
            ? L("日付を入れると、日ごとに並べた下書きになります", "Add dates to get a day-by-day draft.")
            : L("ログインすると、行きたい場所として地図に並びます", "Sign in to see them on your map.")
    }

    /// 挟む札・足元の主な操作の名前
    static func actionTitle(signedIn: Bool) -> String {
        signedIn ? L("旅行プランにする", "Make a trip") : L("ログインして見る", "Sign in to see")
    }

    /// 足元のボタン。未ログインは「地図で見る」（押すとログイン）、ログイン中は「旅行プランにする」
    static func footerAction(signedIn: Bool) -> String {
        signedIn ? L("旅行プランにする", "Make a trip") : L("地図で見る", "See on map")
    }

    /// 足元の数「行きたい 3 か所」
    static func footerCount(_ count: Int) -> String {
        L("行きたい \(count) か所", count == 1 ? "1 place saved" : "\(count) places saved")
    }

    /// ログインの画面の上に出す一言
    static var signInReason: String {
        L("選んだ場所を地図と旅行プランで見るにはログインしてください", "Sign in to see your places on a map and in a trip.")
    }
}
