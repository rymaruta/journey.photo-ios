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
        let pool = spots.filter { TripPicker.isEligible($0) && !ids.contains($0.spotId) }
            .sorted { $0.spotId < $1.spotId }
        guard !pool.isEmpty else { return nil }
        let index = ((day % pool.count) + pool.count) % pool.count
        return pool[index]
    }

    // MARK: - 挟む札・足元

    /// 挟む札の題（何が見られるかで言う）
    static func pauseTitle(wants: Int) -> String {
        L("選んだ \(wants) か所を、地図と旅行プランで",
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
