import Foundation
import Combine

/// 撮影地マップの頭。絞りの条件を持ち、地図は `shown` から描く。
/// リストは同じ条件（上の欄・カテゴリ）で `photos` と撮影スポットを
/// 都道府県ごとにまとめる（`RegionList`）。
///
/// 絞るのは手元の配列だけ。打っている間に通信はしない。
@MainActor
final class PhotoMapViewModel: ObservableObject {

    enum Mode: String, CaseIterable, Identifiable {
        /// 板 04c 案A の並び: 地図 / スポット / リスト
        case map, spots, list
        var id: String { rawValue }
        var label: String {
            switch self {
            case .map: return L("地図", "Map")
            case .spots: return L("スポット", "Spots")
            case .list: return L("リスト", "List")
            }
        }
    }

    @Published private(set) var photos: [Photo] = []
    @Published private(set) var loaded = false
    /// 写真の一覧を取れなかった（圏外で控えも無い）。**0枚とは分ける**
    @Published private(set) var loadFailed = false
    @Published var query = "" { didSet { refresh() } }
    @Published private(set) var category: String?
    @Published var mode: Mode = .map
    /// 「このエリアを検索」で固定した範囲
    @Published private(set) var areaFrame: MapFraming.Frame?

    /// いま地図に見えている範囲。`onMapCameraChange` が届くたびに入れ替わる。
    ///
    /// **`@Published` にしない。** 地図を動かすたびに知らせを出すと、
    /// 画面 → 描き直し → カメラの知らせ → 画面… と回り続ける。
    /// 実機で**マップのタブを押すとアプリが固まった**（CI の UI テストが
    /// 4分待って応答を得られず落ちた・run 37）。**見えている範囲は
    /// 描画に要らない**——押したときに読めればよい。
    private(set) var visibleFrame: MapFraming.Frame?

    /// 「このエリアを検索」を押せるか。**一度 false → true になるだけ**
    /// （ここだけは画面に要るので知らせるが、回り続けない）
    @Published private(set) var canSearchArea = false

    /// 条件に合う写真。座標の無い写真は入らない（`MapSearch` の約束）。
    ///
    /// **計算のたびに絞り直さない。** 画面は1回描くあいだに `shown` と
    /// `pins` を5回以上読む（空の判定・件数・ピン・札）ので、
    /// 計算属性のままだと写真の数だけ何度も走る。
    @Published private(set) var shown: [Photo] = []

    /// ピン（約1km で束ねた写真）
    @Published private(set) var pins: [MapPin] = []

    /// 撮影スポットの索引（`app/data/spots.json`）。**取れなければ空**
    /// ——本番は Web の変更が main に入るまで 404 で、そのあいだピンが
    /// 出ないだけ（写真の機能は止めない）。描画には `officialPins` を使うので
    /// ここは知らせない
    private(set) var officialSpots: [OfficialSpot] = []
    /// 撮影スポットの台帳を読み終えたか（「スポット」の札の「読み込み中」と「無い」を分ける）。
    /// **これは知らせる**——台帳は1回しか届かないので回り続けない。知らせないと、
    /// 台帳が届く前に「スポット」を押した回に空の一覧のまま止まる
    /// （ピンの集合は寄せていないと空のままで、`officialPins` の知らせが来ない）
    @Published private(set) var officialIndexState: IndexState = .loading
    enum IndexState { case loading, ready, failed }

    /// 地図に置く撮影スポットのピン。**寄せたときと、名前で絞ったときだけ**
    /// （`OfficialPins.visible`）。
    ///
    /// **id の集まりが変わったときだけ入れ替える。** `update(visible:)` は
    /// 地図が落ち着くたびに届くので、届くたびに入れ替えると
    /// 描き直し → カメラの知らせ → … と回る（run 37 の固まり方）
    @Published private(set) var officialPins: [OfficialPins.Pin] = []

    /// `officialPins` を何回入れ替えたか。**回り続けていないことを試験で
    /// 数えるためだけ**にある（模型の Combine には `objectWillChange` が無い）
    private(set) var officialPinsUpdates = 0

    /// 索引の取得。**写真を待たせない**ために別の Task で走らせ、届いたら
    /// ピンだけ入れ替える（`load` は写真が届いた時点で戻る）
    private var indexTask: Task<Void, Never>?

    /// 索引が届くまで待つ。**試験のためだけ**（画面は待たない——届いたら
    /// `officialPins` が入れ替わって描き直される）
    func awaitIndex() async {
        await indexTask?.value
    }

    /// 「見つかりませんでした」を出してよいか。**写真もスポットも無いときだけ**
    /// ——名前で絞ってスポットだけ当たった回に、ピンの上に帯を出さない
    var hasNothingToShow: Bool {
        loaded && shown.isEmpty && officialPins.isEmpty
    }

    /// 絞り直す。条件が変わったときにだけ呼ぶ
    private func refresh() {
        shown = MapSearch.photos(photos, filter: MapSearch.Filter(query: query, category: category, frame: areaFrame))
        pins = MapPin.group(shown)
        refreshOfficialPins()
    }

    /// 「このエリアを検索」中はその枠、そうでなければ見えている枠で数える
    private func refreshOfficialPins() {
        let next = OfficialPins.visible(officialSpots, frame: areaFrame ?? visibleFrame, query: query)
        guard OfficialPins.changed(officialPins, next) else { return }
        officialPins = next
        officialPinsUpdates += 1
    }

    /// チップに出すカテゴリ。**座標のある写真だけ**から数える——座標の無い
    /// 写真しか持たないカテゴリのチップは、押しても地図が空になる
    var categories: [String] {
        CategoryChoices.present(in: photos.filter { $0.coords != nil })
    }

    /// 何かで絞っているか（空のときの言葉を「無い」と「見つからない」で分ける）
    var isFiltering: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || category != nil || areaFrame != nil
    }

    /// ブロック／通報の直後に、読み込み済みのピンから落とす（通信しない）
    func drop(hiddenBy hidden: ModerationStore) {
        photos = hidden.visible(photos)
        refresh()
    }

    func load(environment: AppEnvironment) async {
        // **索引は写真と並行に取る。** 直列に待つと、索引が遅い回に写真の
        // ピンと最初の寄せまで遅れる（通信の上限は20秒）。届いたらピンだけ
        // 入れ替える。取れなくても写真は出す——索引は無くても地図は成り立つ
        indexTask = Task { [weak self] in
            let fetched = try? await environment.spots.fetchIndex()
            self?.officialSpots = fetched ?? []
            self?.officialIndexState = fetched == nil ? .failed : .ready
            self?.refreshOfficialPins()
        }
        do {
            photos = try await environment.gallery.fetchPhotos()
            loadFailed = false
        } catch {
            // **取れなかったのを「写真が無い」と言わない**。手元のぶんは残す
            loadFailed = true
        }
        loaded = true
        refresh()
    }

    /// チップ。**押し直すと外れる**（`CategoryChoices.toggle` と同じ約束）
    func select(category choice: String?) {
        guard let choice else {
            category = nil
            refresh()
            return
        }
        let next = CategoryChoices.toggle(current: category ?? "", choice: choice)
        category = next.isEmpty ? nil : next
        refresh()
    }

    /// 地図が落ち着いたときに呼ばれる。**知らせを出さない**
    /// （出すと描き直し → カメラの知らせ → … で回り続ける）。
    /// 押せるようになったことだけは、一度だけ知らせる
    ///
    /// 撮影スポットのピンだけは枠から数える——ただし**集まりが変わった
    /// ときだけ**入れ替える（`refreshOfficialPins`）
    func update(visible frame: MapFraming.Frame) {
        visibleFrame = frame
        if !canSearchArea { canSearchArea = true }
        refreshOfficialPins()
    }

    /// 「このエリアを検索」。**押したときの範囲**で固定する
    func applyArea() {
        guard let visibleFrame else { return }
        areaFrame = visibleFrame
        refresh()
    }

    func clearArea() {
        areaFrame = nil
        refresh()
    }

    /// 札（押した時点のピンの写し）を、いまのピンに差し替えた値。消えていれば nil。
    ///
    /// 🔴 **`MapPin ==` は id（座標）しか比べない**ので、`==` で「変わったか」を
    /// 見ると、同じ座標に前の人あての写真が混ざっていても差し替わらない。
    /// 人が替わったあとに使うので、見つかれば必ずいまのピンを返す
    static func refreshed(_ pin: MapPin?, in pins: [MapPin]) -> MapPin? {
        // 札もこれで描く（押した時点の写しではなく、いまの絞り込みの中身）
        guard let pin else { return nil }
        return pins.first { $0.id == pin.id }
    }

    /// 撮影スポットの札も写真の札（`refreshed`）と同じ約束（いま出ているピンのぶんだけ）
    func stillShown(official pin: OfficialPins.Pin?) -> Bool {
        guard let pin else { return false }
        return officialPins.contains { $0.id == pin.id }
    }

    /// 撮影スポットの札を出すか。
    ///
    /// 🔴 **札から開いた画面を上に積んでいる間（`onScreen == false`）は下げない。**
    /// 札の「スポットを見る」は `NavigationLink` なので、裏で地図が動いて
    /// （遅れて届いた現在地など）ピンが外れると、札ごと消えて開いている画面が閉じる。
    /// 戻ってきたら、いま出ているピンのぶんだけに戻す
    func showsCard(official pin: OfficialPins.Pin?, onScreen: Bool) -> Bool {
        guard pin != nil else { return false }
        return !onScreen || stillShown(official: pin)
    }

    /// ピンの元の行（画面へ渡す。概要・近くのスポットはここから）
    func officialSpot(for pin: OfficialPins.Pin) -> OfficialSpot? {
        officialSpots.first { $0.spotId == pin.spotId }
    }

    /// いまのピンに合わせた枠（無ければ nil＝地図の既定に任せる）。
    ///
    /// **写真が当たらず、名前でスポットだけ当たった回はスポットの座標群で作る**
    /// ——「たかや」と打って高屋神社のピンが出たのに、地図がパリに居たままに
    /// しない。名前で絞っていないとき（寄せただけで出ているピン）には使わない
    var frame: MapFraming.Frame? {
        if let photos = MapFraming.frame(for: pins.map { (latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }) {
            return photos
        }
        guard !MapSearch.fold(query).isEmpty else { return nil }
        return MapFraming.frame(for: officialPins.map { (latitude: $0.coords.lat, longitude: $0.coords.lng) })
    }
}

// MARK: - 地図の文字（単数・複数と読み上げ）

extension PhotoMapViewModel {
    /// 「3枚」／「1 photo」「3 photos」。英語は1枚のとき単数形
    nonisolated static func photoCountLabel(_ count: Int) -> String {
        L("\(count)枚", count == 1 ? "1 photo" : "\(count) photos")
    }

    /// 「2地点」／「1 place」「2 places」。英語は1地点のとき単数形
    nonisolated static func placeCountLabel(_ count: Int) -> String {
        L("\(count)地点", count == 1 ? "1 place" : "\(count) places")
    }

    /// 範囲で絞っているときの帯「この範囲の写真 3枚・2地点」／「3 photos · 1 place here」。
    /// 枚数と地点数は上の2つの関数で数える（単数形をここで書き直さない）
    nonisolated static func areaCountLabel(photos: Int, places: Int) -> String {
        L("この範囲の写真 \(photoCountLabel(photos))・\(placeCountLabel(places))",
          "\(photoCountLabel(photos)) · \(placeCountLabel(places)) here")
    }

    /// ピンの札の「この周辺の写真 3枚」
    nonisolated static func nearbyCountLabel(_ count: Int) -> String {
        L("この周辺の写真 \(count)枚", count == 1 ? "1 photo nearby" : "\(count) photos nearby")
    }

    /// 写真のピンの読み上げ名（「パリ、写真 3枚」）。撮影地が無ければ
    /// 札と同じ「場所の名前なし」
    nonisolated static func pinSpokenLabel(place: String?, count: Int) -> String {
        let name = place?.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = (name?.isEmpty == false) ? name! : L("場所の名前なし", "No place name")
        return L("\(shown)、写真 \(count)枚", "\(shown), \(photoCountLabel(count))")
    }
}
