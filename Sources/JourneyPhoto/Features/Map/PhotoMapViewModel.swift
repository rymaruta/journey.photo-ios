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
    /// 絞りに効いている語。**入れたらその場で絞り直す**（探すから来た語・× で消す・確定）。
    /// 欄に打っている途中の字は `typedQuery` に入り、間引いてからここへ写す
    @Published var query = "" {
        didSet {
            // 欄の字もそろえ、待っている写しは捨てる（古い字で上書きしない）
            queryDebounceTask?.cancel()
            queryDebounceTask = nil
            if typedQuery != query { typedQuery = query }
            refresh()
        }
    }

    /// 検索欄に打っている字（欄の束ね先）。**打つたびには絞り直さない**——
    /// 1字ごとに全件を絞り、ピンを束ね直していた（docs/QUALITY_2026-10-03.md の P2）。
    /// 打つのが `queryDebounce` だけ止まったら `query` へ写す。確定（return）は `commitTypedQuery()`、
    /// × は `query = ""` でその場で効かせる。
    ///
    /// 2026-10-07 判断: 間引きは 250ms。探すの人の検索（`SearchViewModel.search`・300ms）は通信の
    /// ための待ちで、ここは手元の絞りだけなので少し短くする。仕組みは同じ（前の待ちを取り消し、
    /// 眠ってから写す）だが、あちらは通信の回の番号まで持つので関数は分けたまま
    @Published var typedQuery = "" {
        didSet {
            guard typedQuery != oldValue else { return }
            scheduleQueryCommit()
        }
    }

    /// 打つのが止まってから絞るまでの間。**試験のためだけに差し替える**
    var queryDebounce: Duration = .milliseconds(250)
    private var queryDebounceTask: Task<Void, Never>?

    /// 打っている字を、いま絞りに効かせる（return・試験）。同じ語なら何もしない
    func commitTypedQuery() {
        queryDebounceTask?.cancel()
        queryDebounceTask = nil
        guard query != typedQuery else { return }
        query = typedQuery
    }

    /// 間引きの待ちが済むまで待つ。**試験のためだけ**
    func awaitTypedQuery() async {
        await queryDebounceTask?.value
    }

    private func scheduleQueryCommit() {
        queryDebounceTask?.cancel()
        queryDebounceTask = nil
        // `query` の didSet から揃えた回（同じ字）は待たない
        guard typedQuery != query else { return }
        let delay = queryDebounce
        queryDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.commitTypedQuery()
        }
    }

    /// 絞り直した回数。**打つたびに絞り直していないことを試験で数えるためだけ**
    private(set) var refreshCount = 0
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
    @Published private(set) var pins: [MapPin] = [] { didSet { cachedPhotoFrame = nil } }

    /// 地図に**置く**写真の印（`MapPinClusters.layout`）。多すぎるときだけ近いピンを束ねる。
    /// 札・枠・件数は今までどおり `pins` から（束はピンを選ばない）。
    ///
    /// **組み方が変わったときだけ入れ替える**（`officialPins` と同じ・run 37 の固まり方）
    @Published private(set) var pinLayout = MapPinClusters.Layout()

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
    /// 撮影スポットの別名（slug → 別名・`OfficialSpotService.fetchAliases`）。取れなければ空で、
    /// 名前・読み・地域だけで当てる。**「さがす」と同じ当て方にする**——別名で当たったスポットを
    /// 地図へ持ってきた回に「見つかりませんでした」にしない。届くのは1回なので知らせる
    @Published private(set) var spotAliases: [String: [String]] = [:]
    /// 別名を取り終えたか（取れなかった回も立つ）。語への寄せの当たり外れはこれを待って決める
    @Published private(set) var aliasesSettled = false
    enum IndexState { case loading, ready, failed }

    /// 地図に置く撮影スポットのピン。**寄せたときと、名前で絞ったときだけ**
    /// （`OfficialPins.visible`）。
    ///
    /// **id の集まりが変わったときだけ入れ替える。** `update(visible:)` は
    /// 地図が落ち着くたびに届くので、届くたびに入れ替えると
    /// 描き直し → カメラの知らせ → … と回る（run 37 の固まり方）
    @Published private(set) var officialPins: [OfficialPins.Pin] = [] { didSet { cachedSpotFrame = nil } }

    /// `officialPins` を何回入れ替えたか。**回り続けていないことを試験で
    /// 数えるためだけ**にある（模型の Combine には `objectWillChange` が無い）
    private(set) var officialPinsUpdates = 0

    /// 索引の取得。**写真を待たせない**ために別の Task で走らせ、届いたら
    /// ピンだけ入れ替える（`load` は写真が届いた時点で戻る）
    private var indexTask: Task<Void, Never>?
    /// 読み込みの回の番号。**新しい回が始まったら、古い回の答えは書かない**——
    /// 「もう一度試す」を続けて押すと、遅れて返った古い回（失敗）が新しい回（成功）を
    /// 上書きしていた（2026-10-02 のレビュー）
    private var loadGeneration = 0
    /// 写真を読んでいる最中（「もう一度試す」を止める）
    @Published private(set) var isLoading = false

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
        refreshCount += 1
        shown = MapSearch.photos(photos, filter: MapSearch.Filter(query: query, category: category, frame: areaFrame))
        pins = MapPin.group(shown)
        pinLayout = MapPinClusters.layout(pins, frame: visibleFrame)
        refreshOfficialPins()
    }

    /// 地図が動いたときの束ね直し。**組み方が変わらなければ知らせない**
    private func refreshPinLayout() {
        let next = MapPinClusters.layout(pins, frame: visibleFrame)
        guard next != pinLayout else { return }
        pinLayout = next
        pinLayoutUpdates += 1
    }

    /// `pinLayout` を地図の動きで何回入れ替えたか。**回り続けていないことを試験で数えるためだけ**
    private(set) var pinLayoutUpdates = 0

    /// 「このエリアを検索」中はその枠、そうでなければ見えている枠で数える。
    ///
    /// 🔴 **カテゴリで絞っている間は撮影スポットのピンを置かない**（Web の `filterMapSpots` と同じ）。
    /// チップは**写真の分類**（風景・建築…）で、台帳の `category`（神社・温泉街…）とは別の持ち物——
    /// 対応表を作ると嘘の対応が混ざる。以前は写真のピンだけ絞れ、「風景」を選んでも
    /// スポットのピンは全部残り、そのカテゴリのスポットに見えていた
    private func refreshOfficialPins() {
        let next = category != nil ? [] : OfficialPins.visible(officialSpots, frame: areaFrame ?? visibleFrame,
                                                               query: query, aliases: spotAliases)
        requestPinDetails(next)
        guard OfficialPins.changed(officialPins, next) else { return }
        officialPins = next
        officialPinsUpdates += 1
    }

    // MARK: - ピンの詳細（分けた置き場・2026-10-07）

    /// 索引を読んだサービス（ピンの詳細を読むのに使う）
    private var spotService: OfficialSpotService?
    /// ピンの詳細を読んでいる回
    private var pinDetailTask: Task<Void, Never>?
    /// 最後に読みに行った行の鍵。**同じ集まりで叩き直さない**（取れなかった区分で回り続けない）
    private var pinDetailKey = ""

    /// 置いたピンのうち、まだ索引だけの行（写真が無い）の詳細を読み、届いたらピンを入れ替える。
    /// 詳細の和が小さいうちはサービスが全区分を読んでいるので、何もしない（`SpotDetailNeeds`）
    private func requestPinDetails(_ pins: [OfficialPins.Pin]) {
        guard let service = spotService, !pins.isEmpty else { return }
        let ids = Set(pins.map(\.spotId))
        let needs = SpotDetailNeeds.indexOnly(officialSpots.filter { ids.contains($0.spotId) })
        let key = SpotDetailNeeds.key(needs)
        guard !needs.isEmpty, key != pinDetailKey else { return }
        pinDetailKey = key
        let generation = loadGeneration
        pinDetailTask = Task { [weak self] in
            guard let self else { return }
            let merged = await service.withDetails(self.officialSpots, for: needs)
            // 待っている間に読み直しが始まっていたら書かない（新しい回の索引を古い行で上書きしない）
            guard self.loadGeneration == generation else { return }
            self.officialSpots = Self.overlay(self.officialSpots, with: merged)
            self.refreshOfficialPins()
        }
    }

    /// 今の行に、重ねた行（詳細あり）だけを差し込む（待っている間に変わった行を古い写しで戻さない）
    private static func overlay(_ current: [OfficialSpot], with merged: [OfficialSpot]) -> [OfficialSpot] {
        let detailed = Dictionary(merged.filter { !$0.isIndexOnly }.map { ($0.spotId, $0) },
                                  uniquingKeysWith: { first, _ in first })
        guard !detailed.isEmpty else { return current }
        return current.map { row in
            guard row.isIndexOnly, let hit = detailed[row.spotId] else { return row }
            return hit
        }
    }

    /// ピンの詳細が届くまで待つ。**試験のためだけ**
    func awaitPinDetails() async {
        await pinDetailTask?.value
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
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        // 前の回の索引は取り消す（答えが来ても下の世代の見張りで書かない）
        indexTask?.cancel()
        spotService = environment.spots
        pinDetailKey = ""
        // **索引は写真と並行に取る。** 直列に待つと、索引が遅い回に写真の
        // ピンと最初の寄せまで遅れる（通信の上限は20秒）。届いたらピンだけ
        // 入れ替える。取れなくても写真は出す——索引は無くても地図は成り立つ
        indexTask = Task { [weak self] in
            let fetched = try? await environment.spots.fetchIndex()
            guard let self, self.loadGeneration == generation else { return }
            self.officialSpots = fetched ?? []
            self.refreshOfficialPins()
            self.officialIndexState = fetched == nil ? .failed : .ready
            // 別名は索引のあと（索引のピンを待たせない）。届いたらピンを数え直し、
            // **取り終えた印を立てる**——語への寄せが「当たらなかった」と決めてよいのは
            // 別名まで見てから（探すから別名だけで当たる語が来た回に、寄せが下りていた）
            let aliases = fetched == nil ? [:] : await environment.spots.fetchAliases()
            guard self.loadGeneration == generation else { return }
            if !aliases.isEmpty {
                self.spotAliases = aliases
                self.refreshOfficialPins()
            }
            self.aliasesSettled = true
        }
        let result: Result<[Photo], Error>
        do {
            result = .success(try await environment.gallery.fetchPhotos())
        } catch {
            result = .failure(error)
        }
        // 待っている間に新しい回が始まっていたら書かない（新しい回が書く）
        guard loadGeneration == generation else { return }
        switch result {
        case .success(let fetched):
            photos = fetched
            loadFailed = false
        case .failure:
            // **取れなかったのを「写真が無い」と言わない**。手元のぶんは残す
            loadFailed = true
        }
        isLoading = false
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
        refreshPinLayout()
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
    ///
    /// **覚えておく。** 画面は描き直すたびにこれを読み（`PhotoMapView.statusLine`）、塊の計算は
    /// 写真の地点が世界に数百あると Debug で1回 60ms ほどかかる（run 206 で地図の画面が
    /// 落ち着かなくなった回の調べ）。写真の枠は `pins` が、スポットの枠は `officialPins` が
    /// 入れ替わったときだけ捨てる（`query` が変わると `refresh` が必ず `pins` を入れ直す）。
    /// 分けて覚えるのは、地図を動かすたびに入れ替わる `officialPins` で写真の枠まで捨てないため
    var frame: MapFraming.Frame? {
        if let photos = photoFrame { return photos }
        guard !MapSearch.fold(query).isEmpty else { return nil }
        return spotFrame
    }

    /// 写真の枠。塊の重さはピンの写真の枚数（ピンの数ではない）
    private var photoFrame: MapFraming.Frame? {
        if let cachedPhotoFrame { return cachedPhotoFrame }
        let value = MapFraming.frame(for: pins.map { (latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) },
                                     weights: pins.map(\.photos.count))
        cachedPhotoFrame = .some(value)
        frameComputations += 1
        return value
    }

    /// 名前で当たったスポットの枠
    private var spotFrame: MapFraming.Frame? {
        if let cachedSpotFrame { return cachedSpotFrame }
        let value = MapFraming.frame(for: officialPins.map { (latitude: $0.coords.lat, longitude: $0.coords.lng) })
        cachedSpotFrame = .some(value)
        frameComputations += 1
        return value
    }

    /// 覚えている枠（外側の nil は「まだ計算していない」）
    private var cachedPhotoFrame: MapFraming.Frame??
    private var cachedSpotFrame: MapFraming.Frame??
    /// 枠を何回計算したか。**描き直しのたびに計算していないことを試験で数えるためだけ**にある
    private(set) var frameComputations = 0
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

    /// 束ねたピン（`MapPinClusters`）の読み上げ名（「3地点の写真 12枚。押すと寄ります」）
    nonisolated static func clusterSpokenLabel(photos: Int, places: Int) -> String {
        L("\(placeCountLabel(places))の写真 \(photos)枚。押すと寄ります",
          "\(photoCountLabel(photos)) at \(placeCountLabel(places)). Tap to zoom in")
    }

    /// 写真のピンの読み上げ名（「パリ、写真 3枚」）。撮影地が無ければ
    /// 札と同じ「場所の名前なし」
    nonisolated static func pinSpokenLabel(place: String?, count: Int) -> String {
        let name = place?.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = (name?.isEmpty == false) ? name! : L("場所の名前なし", "No place name")
        return L("\(shown)、写真 \(count)枚", "\(shown), \(photoCountLabel(count))")
    }
}
