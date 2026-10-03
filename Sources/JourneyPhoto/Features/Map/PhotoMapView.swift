import SwiftUI
import MapKit

/// 撮影地の地図（モック3）。
///
///     検索窓 → カテゴリのチップ → 地図 / リスト → 地図（またはリスト）
///
/// **座標は約1km に丸めてある**ので、点が重なる。ピンを重ねて置くと
/// 数が分からなくなるため、同じ座標の写真はまとめて1つの印にする。
///
/// **モックにあって出さないもの**: 「500m以内・8件」「半径5km」のような
/// 距離の数（測っていない）、スポットの評価・口コミ（集計していない）。
/// 出す数は全部 `shown` から数えたもの。
struct PhotoMapView: View {

    /// 見出しはどの画面でも同じ（`AppHeaderItems`）
    var unread: Int = 0
    var onOpenNotifications: () -> Void = {}
    /// 投稿の入口（`RootView` の2択）。地点に写真が無いときの「写真を投稿する」から開く
    var onPost: () -> Void = {}

    @EnvironmentObject private var environment: AppEnvironment
    /// 下の「マップ」をもう一度押した合図（`MapTabReselect`）
    @ObservedObject private var tabRouter = TabRouter.shared
    /// ブロック／通報したぶんをピンから落とすため（`needsDrop`）
    @EnvironmentObject private var hidden: ModerationStore
    /// ブロック／通報があったが、まだピンから落としていない。
    /// **見ている最中には絞らない**（`FavoritesView` の `photos` の注記）——
    /// 押した元の `NavigationLink` が消えると、開いている詳細がその場で閉じ、
    /// 通報の「受け付けました」も見えない。戻ってきたとき（`onAppear`）に絞る
    @State private var needsDrop = false
    /// ピンを読んだときの人（`ModerationStore.userRevision`）。**人が替わったら
    /// 絞るだけでなく読み直す**——前の人あての「フォロワーのみ」は、
    /// 次の人のブロック・通報では落ちない
    @State private var loadedUserRevision = 0
    /// `onChange(of: hidden.revision)` が最後に見た人の数。**数の進みが人の入れ替わりか
    /// ブロックかを見分けるため**（`loadedUserRevision` は読み込みが落ちると遅れるので、
    /// それで見るとブロック1回を入れ替わりと取り違える）
    @State private var seenUserRevision = 0
    /// いまこの画面が出ているか。**上に画面を積んでいる間は札を下げない**
    /// （`PhotoMapViewModel.showsCard(official:onScreen:)`）。
    /// **出ていない間は人が替わっても読み直さない**——札の `NavigationLink` の先を
    /// 開いている間に札を下げると、その場で閉じる。戻ってきたとき `.task` が読み直す
    @State private var isOnScreen = false
    @StateObject private var model = PhotoMapViewModel()
    @StateObject private var location = CurrentLocation()
    /// 取れた現在地。**この画面が開いている間だけ**持つ
    /// （保存も送信もしない——`CurrentLocation` の約束をここでも守る）
    @State private var here: Photo.Coords?
    @State private var showNearby = false
    /// 「近くに写真はありません」の帯を下げたか。「全体を見る」を押したか、
    /// 指で地図を動かしたら下げる（現在地を取り直したら、また出す）
    @State private var noneNearbyBanner = NearbyPhotos.NoneNearbyBanner()
    /// 押したピン。**下の札に出す**（シートで画面を覆うと地図が見えない）
    @State private var selected: MapPin?
    /// 押した撮影スポットのピン（台帳）。札は同時に1枚——写真のピン・
    /// Apple の地点と取り合わせず、どれかを押したら他は下げる
    @State private var selectedOfficial: OfficialPins.Pin?
    /// 撮影スポットの「経路」の検索。押し直し・札の切り替え・画面を離れたら止める
    @State private var directionsTask: Task<Void, Never>?
    /// 一覧を開くとき（札の「写真を見る →」）
    @State private var listing: MapPin?
    /// リストの県の開閉。**押した県**だけを持つ（押した県は起点が動いても押したまま）
    @State private var regionOpen: [String: Bool] = [:]
    /// 起点の県として一度でも開いた県。**起点が替わっても閉じない**——閉じると、
    /// その県から開いていた詳細が元の行ごと消えてその場で閉じる
    @State private var autoOpenedRegions: Set<String> = []
    /// 押した地点（Apple の地図が描く POI）。**iOS 18 以降だけ**入る
    /// （`PlaceSelectableMap`）。ピンの札とは同時に出さない
    @State private var chosenPlace: ChosenPlace?
    /// Apple の詳細カードに出す地点（札の「場所の詳細」）
    @State private var placeDetail: MKMapItem?
    /// 地図の見ている場所。**現在地が取れたらそこ、取れなければ写真に合わせる**
    /// （以前は写真に合わせるだけ・指示書 9-2。既定を自分の今の場所にしたのは
    /// owner の判断 2026-09-26）
    @State private var camera: MapCameraPosition = .automatic
    /// 開いたときに現在地を取りにいったか。**最初の1回だけ**——タブを
    /// 行き来するたびに取り直して、指で動かした場所から引き戻さない
    @State private var autoLocateStarted = false
    /// 写真の範囲へ一度寄せたか。**寄せるのは最初の1回だけ**——詳細から戻るたびに
    /// `.task` が走り直し、見ていた場所から写真の範囲へ引き戻していた
    @State private var framedToPhotos = false
    /// 探すから受け取った語で寄せる印（`MapQueryFraming`）。読み込みの前に受け取った回は
    /// 枠が決まってから寄せ、開いたときの自動の現在地で上書きしない
    @State private var queryFraming = MapQueryFraming()
    /// 拡大・縮小を続けて押したときの土台（`MapFraming.ZoomChain`）
    @State private var zoomChain = MapFraming.ZoomChain()
    /// 方位磁針を地図の外（右の操作列）に置くための名前。
    /// 置かないと、iOS が右上に出す方位磁針が操作列と重なる
    @Namespace private var mapScope

    var body: some View {
        VStack(spacing: 0) {
            searchField
            // カテゴリは写真の分類。「スポット」の札では効かないので出さない
            if model.mode != .spots {
                categoryChips
            }
            modePicker
            switch model.mode {
            case .map: mapArea
            case .spots: spotsArea
            case .list: listArea
            }
        }
        .webScreen()
        .navigationTitle(Labels.Navigation.mapTab)  // 見た目はロゴ（AppHeaderItems）。この字は次の画面の「戻る」と読み上げに使う
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { AppHeaderItems(unread: unread, onOpenNotifications: onOpenNotifications) }
        .task {
            if !autoLocateStarted {
                autoLocateStarted = true
                location.locate(requestedByUser: false)
            }
            let revision = hidden.userRevision
            seenUserRevision = revision
            let userChanged = loadedUserRevision != revision
            await model.load(environment: environment)
            // 🔴 **取り消された回（戻るスワイプを途中でやめた）は何もしない。**
            // 札を差し替えると開いている詳細が閉じ、印だけ進めると本当に戻った
            // ときに読み直さない
            // 読んでいる間にまた人が替わった回も触らない（そちらの `reloadForNewUser`
            // が進めた印を、古い数で戻さない）
            if userChanged, !Task.isCancelled, !model.loadFailed, hidden.userRevision == revision {
                loadedUserRevision = revision
                // 見ていない間に人が替わった: 札は前の人の一覧から作ったので、読み直した
                // ピンに差し替える（下げると、戻るスワイプの途中で詳細が閉じる）
                refreshSelected()
            }
            // 読んでいる間に通報された回、古い集合で絞った結果を残さない
            dropHidden()
            // 探すから語を受け取っていれば、その当たりへ寄せる（現在地が先でも）
            frameToQueryIfReady()
            // 現在地が先に取れていたら、写真の読み込みで引き戻さない
            if here == nil, !framedToPhotos, let photosFrame = model.frame {
                framedToPhotos = true
                frame(photosFrame)
            }
        }
        // 絞りが変わったら、残ったピンに寄せ直す（範囲で絞ったときは
        // 見ている場所を動かさない——押した範囲がそのまま答え）
        .onChange(of: hidden.revision) { _, _ in
            needsDrop = true
            // 🔴 **人が替わったら、見ている最中でも読み直す。** ログアウトは
            // 見出しのメニュー（シート）から来るので、閉じても `onAppear` も
            // `.task` も来ず、前の人あての限定写真のピンが残っていた。
            // 見ていない間は `.task`（戻ってきたとき）に任せる
            let userChanged = hidden.userRevision != seenUserRevision
            seenUserRevision = hidden.userRevision
            if isOnScreen, userChanged { reloadForNewUser() }
        }
        .onAppear {
            isOnScreen = true
            tabRouter.mapRootOnScreen = true
            if needsDrop { dropHidden() }
            applyPendingQuery()
        }
        // 探すの0件の出口から来た回。地図がもう出来ていれば `onAppear` より先にここで受ける
        .onChange(of: tabRouter.mapRequests) { _, _ in
            applyPendingQuery()
        }
        .onDisappear {
            isOnScreen = false
            tabRouter.mapRootOnScreen = false
            directionsTask?.cancel()
        }
        // 札を切り替えた・閉じたら、前の札の「経路」の検索は捨てる
        .onChange(of: selectedOfficial) { _, _ in
            directionsTask?.cancel()
        }
        .onChange(of: model.query) { _, query in
            // 欄を空にした（× や手で消した）ら、探すから来た語の寄せ待ちも下ろす
            if query.isEmpty { queryFraming.cleared() }
            guard model.areaFrame == nil else { return }
            frame(model.frame)
        }
        .onChange(of: model.category) { _, _ in
            guard model.areaFrame == nil else { return }
            frame(model.frame)
        }
        // リストへ切り替えたら地点の札は下げる（地図に戻ると選択の印が
        // 消えているので、札だけ残ると何を指しているか分からない）
        .onChange(of: model.mode) { _, _ in
            chosenPlace = nil
            // 札を下げたのと同じ。検索の途中で「スポット」「リスト」へ移ったのに、
            // 後から地図アプリが開いていた
            directionsTask?.cancel()
        }
        // 索引を読み直してピンの中身（写真・出典・下書き）が変わったら、開いている札も
        // 新しい中身に差し替える（札だけ古い写真と出典のまま残らないように）
        // 索引が届いてもピンが空のまま（語がスポットにも当たらない）だと上の知らせは来ない。
        // 取り終えたことで「何にも当たらなかった」と決める
        .onChange(of: model.aliasesSettled) { _, _ in
            frameToQueryIfReady()
        }
        .onChange(of: model.officialIndexState) { _, _ in
            frameToQueryIfReady()
        }
        .onChange(of: model.officialPins) { _, _ in
            // 探すからの語がスポットの名前だけで当たる回は、索引が届いて初めて枠が決まる。
            // 写真の読み込みの後に限る（先に索引で寄せると、写真で当たる回に寄せ直せない）
            frameToQueryIfReady()
            guard let selected = selectedOfficial,
                  let fresh = model.officialPins.first(where: { $0.id == selected.id }),
                  fresh != selected else { return }
            selectedOfficial = fresh
        }
        // 現在地が取れたら、そこへ寄せる。**絞りはしない**——代わりに
        // 「近くの写真」の入口を出す（押すまで何も変えない）
        //
        // **寄せたあとは自分の位置を追う**（普通の地図アプリと同じ）。
        // 追うのは地図（MapKit）の中だけで、位置は保存も送信もしない
        .onChange(of: location.state) { _, state in
            guard case .located(let latitude, let longitude) = state else { return }
            here = Photo.Coords(lat: latitude, lng: longitude)
            // 探すからの語で寄せている間・指で動かしたあとは、開いたときの自動の現在地で
            // 上書きしない（ボタンで取った回は寄せる）
            guard queryFraming.followsLocation(requestedByUser: location.requestedByUser) else { return }
            // 「近くに写真はありません」を出し直すのは、現在地へ寄せる回だけ。
            // 寄せない回に出し直すと、指で動かして下げた帯が、動かない地図の上に戻っていた
            noneNearbyBanner.located()
            zoomChain.reset()
            camera = .userLocation(fallback: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))))
        }
        // **地図を開いたまま「マップ」をもう一度押したら現在地へ**
        // （`TabRouter.mapLocateRequests`）。位置情報が切られていれば、
        // ボタンを押した回と同じく `locationNote` が言葉にする
        .onChange(of: tabRouter.mapLocateRequests) { _, _ in
            switch MapTabReselect.action(onScreen: isOnScreen,
                                         isMapMode: model.mode == .map,
                                         followsLocation: camera.followsUserLocation,
                                         followsHeading: camera.followsUserHeading) {
            case .ignore:
                break
            case .stopHeading:
                zoomChain.reset()
                camera = .userLocation(fallback: camera.fallbackPosition ?? camera)
            case .locate:
                zoomChain.reset()
                location.locate()
            }
        }
        // 近くの写真のシートの中でブロックした回も同じ（地図は見え続けている）
        .sheet(isPresented: $showNearby, onDismiss: { if needsDrop { dropHidden() } }) {
            if let here {
                NearbyPhotosSheet(center: here, photos: model.photos,
                                  couldNotLoad: !model.loaded || model.loadFailed,
                                  onRetry: model.loaded && model.loadFailed ? { retryLoad() } : nil)
            }
        }
        // 一覧のシートの中の詳細でブロックした回は、地図は見え続けていて
        // `onAppear` が来ない。閉じたときに落とす
        .sheet(item: $listing, onDismiss: { if needsDrop { dropHidden() } }) { pin in
            NavigationStack {
                // シートの中の詳細でブロックして戻ったら、ここでも落とす（`VisiblePhotos`）
                VisiblePhotos(photos: pin.photos) { photos in
                List(photos) { photo in
                    NavigationLink {
                        PhotoDetailView(photo: photo, context: photos)
                    } label: {
                        HStack(spacing: 10) {
                            RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(photo.displayTitle.isEmpty ? (photo.location ?? L("写真", "Photo")) : photo.displayTitle)
                        }
                    }
                }
                }
                .navigationTitle(pin.hasPlaceName ? pin.title : L("場所の名前なし", "No place name"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
                }
            }
        }
    }

    // MARK: - 絞る口

    /// 探すから渡された語で絞り、地図の表示にする（一度きり・根が出ているときだけ）。
    /// 範囲（このエリアを検索）とカテゴリは外す——残すと語で当たる所が範囲の外で0件になる
    private func applyPendingQuery() {
        guard let query = tabRouter.takePendingMapQuery(rootOnScreen: tabRouter.mapRootOnScreen) else { return }
        model.clearArea()
        model.select(category: nil)
        model.query = query
        model.mode = .map
        // 空の語（タグ・語なしで探した回）は前の語を消すだけ（前の語の寄せ待ちも下ろす）
        queryFraming.received(query: query)
        guard !query.isEmpty else { return }
        // 読み込み済みならその場で寄せる。まだなら `.task` と索引の知らせが寄せる
        frameToQueryIfReady()
    }

    /// 探すからの語の当たりへ寄せる（`MapQueryFraming`）。写真を読み終えてから。
    /// 索引も取り終えて何にも当たらないと決まったら、印を下ろす（現在地の自動の寄せも戻す）
    private func frameToQueryIfReady() {
        guard model.loaded else { return }
        // 別名まで取り終えてから「当たらなかった」と決める（別名だけで当たる語がある）
        let settled = model.officialIndexState != .loading && model.aliasesSettled
        guard let queryFrame = queryFraming.frameIfReady(model.frame, settled: settled) else { return }
        framedToPhotos = true
        frame(queryFrame)
    }

    /// **撮影地の文字列とスポットの名前だけ**で絞る（通信しない）。
    /// 「都市」で当たるのは撮影地にその語が入っているときだけなので、
    /// プレースホルダにもそう書く
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WebTheme.faint)
            TextField(L("撮影地・スポット名で絞る", "Filter by place or spot"),
                      text: $model.query)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("map.search")
                .foregroundStyle(WebTheme.foreground)
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(WebTheme.faint)
                        .webTappable()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("消す", "Clear"))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(WebTheme.surface, in: Capsule())
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// カテゴリ。**「すべて」を先頭に置く**（戻れない絞り込みを作らない）。
    /// 出すのは座標のある写真に実際にある種類だけ
    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(Labels.Category.all, selected: model.category == nil) {
                    model.select(category: nil)
                }
                ForEach(model.categories, id: \.self) { category in
                    chip(Labels.Category.name(category),
                         symbol: CategoryChoices.symbol(category),
                         selected: model.category.map {
                             CategoryChoices.isChosen(current: $0, choice: category)
                         } ?? false) {
                        model.select(category: category)
                    }
                }
            }
            .padding(.horizontal, 16)
            // 札の押せる余白（上下 4）の分だけ詰め、札の上下の見た目の間は前のまま 10。
            // ScrollView の外で負の余白にすると、上の検索欄の下端に ScrollView が重なって当たりを取る
            .padding(.vertical, 10 - PillChip.tapSlack)
        }
    }

    /// 探す画面のチップと同じ形（白地＝選択中）。見た目の札は上下 11 ＋ 字（字の大きさが
    /// 標準で約 42）、上下 4 の余白まで押せる＝**押せる範囲は 44 以上**（`PillChip` と同じ形）
    private func chip(_ title: String, symbol: String? = nil, selected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                // **記号は持っている分類にだけ**（`CategoryChoices.symbol`）。
                // 知らない語に当てずっぽうの絵を付けない
                if let symbol {
                    Image(systemName: symbol).font(.caption)
                }
                Text(title)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
            }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(selected ? AnyShapeStyle(WebTheme.foreground)
                                     : AnyShapeStyle(WebTheme.surface),
                            in: Capsule())
                .foregroundStyle(selected ? WebTheme.accentText : WebTheme.muted2)
                .padding(.vertical, PillChip.tapSlack)
                .frame(minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 「地図 / スポット / リスト」（板 04c 案A: 高さ 44 のガラスの帯に3つ、選んでいる札は
    /// 白地に墨の字）。地図は `shown` から、スポットは撮影スポットの台帳から、
    /// リストは両方を都道府県ごとにまとめて描く（`RegionList`）。
    /// **既定の `segmented` を使わない**——黒地の上で帯だけ明るく浮く
    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(PhotoMapViewModel.Mode.allCases) { mode in
                let selected = model.mode == mode
                Button {
                    model.mode = mode
                } label: {
                    Text(mode.label)
                        .font(.footnote.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? WebTheme.accentText : Color.white.opacity(0.82))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(selected ? Color.white.opacity(0.92) : Color.clear, in: Capsule())
                        // 見た目の札は 36（板 04c）、上下 4 の余白まで押せる＝**押せる範囲は 44**（CLAUDE.md）。
                        // 余白で広げる——字を大きくしても札が帯の縁に接しない
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("map.mode.\(mode.rawValue)")
            }
        }
        // 上下の余白は札の側（押せる範囲）に持たせる。帯は 36＋4＋4＝44 のまま（板 04c）
        .padding(.horizontal, 4)
        .jpGlass(in: Capsule())
        .padding(.horizontal, 16)
        // **「スポット」のときだけ上を空ける**（owner の「枠同士が近すぎる」・2026-09-28）。
        // 地図・リストはカテゴリのチップの下の余白（10pt）がそのまま間になるが、
        // スポットはチップを出さないので検索欄に隙間なしで付いていた
        .padding(.top, model.mode == .spots ? 12 : 0)
        .padding(.bottom, 8)
    }

    // MARK: - 地図

    private var mapArea: some View {
        mapCanvas
        // 方位磁針・現在地・拡大縮小を**1本の列にまとめる**（`mapControls`）
        .mapScope(mapScope)
        .overlay(alignment: .top) { statusLine }
        .overlay(alignment: .topTrailing) {
            mapControls
                .padding(.trailing, 16)
                .padding(.top, 56)
        }
        // **下の帯にまとめる**（モック3）。上に置いていた「このエリアを検索」は
        // 左上のピンと重なっていた（実機の絵・run 45）。札が出ているときは
        // その上に乗る
        .overlay(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom) {
                    areaControl
                    Spacer(minLength: 8)
                    // 近くの写真への入口。**現在地が取れた回だけ**出す
                    if here != nil {
                        nearbyButton
                    }
                }
                .padding(.horizontal, 16)

                // **消えたピンの札は出さない。** 絞り込みを変えるとピンは
                // 入れ替わるが、札は値の写しなので残ってしまう。
                // 撮影スポットの札は、そこから開いた画面を積んでいる間だけ残す（`showsCard`）
                // **札は model.pins から引き直した最新のピンで描く。** `selected` は
                // 押した時点の写しで、`MapPin ==` は id（座標）しか比べないので、
                // 絞り込みで同じ座標の写真が減っても写しは古い枚数・写真のままだった
                // **選びは絞りの間も持ち続け、見える結果に入れば札を出す**（2026-09-30 判断:
                // 絞りで下ろすと、日本語入力・×・倍率・範囲との組み合わせで回帰が続いたため）
                if let current = PhotoMapViewModel.refreshed(selected, in: model.pins) {
                    pinCard(current)
                        .padding(.horizontal, 16)
                } else if let selectedOfficial,
                          model.showsCard(official: selectedOfficial, onScreen: isOnScreen) {
                    officialCard(selectedOfficial)
                        .padding(.horizontal, 16)
                } else if let chosenPlace {
                    placeCard(chosenPlace)
                        .padding(.horizontal, 16)
                }
            }
            // **地図の出どころの表示を覆わない。** Apple の地図は左下に
            // 「法律に基づく情報」を出す決まりで、実機の絵（run 47）では
            // 「このエリアを検索」がそこへ重なっていた
            .padding(.bottom, 34)
        }
        // **選んだピンが束に吸われた（または多すぎて枠の外で置かれなくなった）ら選びを外す**
        // ——札が地図に無いピンを指さない（2026-10-02 のレビュー）。絞りで結果から外れたぶんは
        // 持ち続ける（2026-09-30 判断）ので、`pins` に居るのに置かれていないときだけ
        .onChange(of: model.pinLayout) { _, layout in
            if layout.hides(selected, among: model.pins) { selected = nil }
        }
        // 地点を選んだら、ピンの札は下げる（札は1枚だけ）
        .onChange(of: chosenPlace) { _, place in
            if place != nil {
                selected = nil
                selectedOfficial = nil
            }
        }
    }

    /// **地点を押せるのは iOS 18 以降。** 17 では今まで通りの地図
    /// （Apple の地点は描かれるが押しても何も起きない）
    @ViewBuilder
    private var mapCanvas: some View {
        if #available(iOS 18.0, *) {
            PlaceSelectableMap(camera: $camera,
                               scope: mapScope,
                               chosen: $chosenPlace,
                               detail: $placeDetail,
                               onCameraChange: cameraChanged) {
                pinMarkers
            }
        } else {
            Map(position: $camera, scope: mapScope) {
                pinMarkers
            }
            .mapControls {
                // 既定の方位磁針は消す——`mapControls` の列に置いた方を使う
                MapCompass().mapControlVisibility(.hidden)
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                cameraChanged(context)
            }
        }
    }

    /// 写真のピン。同じ座標の写真は1つにまとめてある（`MapPin.group`）
    ///
    /// **自分の位置（青い点と向き）も描く。** 以前は現在地のボタンで地図を
    /// 寄せるだけで、**自分がどこにいてどちらを向いているか**が地図に
    /// 出なかった（owner の指摘・2026-09-25）。点は位置の権限があるときだけ
    /// 出て、これ自体は権限を尋ねない
    ///
    /// **撮影スポット（台帳）のピンは3つ目。** 出るのは寄せたときと名前で
    /// 絞ったときだけで、その判断は頭（`OfficialPins.visible`）にある。
    /// 名前は写真のピンと同じく `Annotation` の題として MapKit が下に描く
    @MapContentBuilder
    private var pinMarkers: some MapContent {
        UserAnnotation()
        // **置くのは `pinLayout`**——多すぎるときだけ近いピンを束ねてある（`MapPinClusters`）
        ForEach(model.pinLayout.pins) { pin in
            Annotation(pin.title, coordinate: pin.coordinate) {
                Button {
                    selected = pin
                    selectedOfficial = nil
                    chosenPlace = nil
                } label: {
                    ZStack(alignment: .topTrailing) {
                        // 44pt の印に 512px は要らない（256px の `thumbSm` から）
                        RemoteImage(url: pin.photos.first?.pinImageURL,
                                    alignment: pin.photos.first?.gridAlignment ?? .center)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        // **数えた枚数**（モックのクラスタの数字にあたる）
                        if pin.photos.count > 1 {
                            CountBadge(count: pin.photos.count)
                                .offset(x: 8, y: -8)
                        }
                    }
                }
                .buttonStyle(.plain)
                // 読み上げは撮影地と枚数（見た目は写真だけで、名前は無かった）
                .accessibilityLabel(PhotoMapViewModel.pinSpokenLabel(
                    place: pin.hasPlaceName ? pin.title : nil, count: pin.photos.count))
                // UI テスト（`ScreenshotTests`）が写真のピンを数える目印
                .accessibilityIdentifier("map.photoPin")
            }
        }
        // 束。押すとその束が収まる枠まで寄る（札は出さない——ピンを選んだことにしない）
        ForEach(model.pinLayout.clusters) { cluster in
            Annotation("", coordinate: CLLocationCoordinate2D(latitude: cluster.latitude,
                                                              longitude: cluster.longitude)) {
                Button {
                    frame(cluster.frame)
                } label: {
                    ZStack(alignment: .topTrailing) {
                        // 後ろに1枚ずらして重ね、1つの撮影地のピンと見分ける
                        RoundedRectangle(cornerRadius: 8)
                            .fill(WebTheme.raised)
                            .frame(width: 44, height: 44)
                            .offset(x: 3, y: 3)
                        RemoteImage(url: cluster.cover?.pinImageURL,
                                    alignment: cluster.cover?.gridAlignment ?? .center)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        CountBadge(count: cluster.photoCount)
                            .offset(x: 8, y: -8)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(PhotoMapViewModel.clusterSpokenLabel(photos: cluster.photoCount,
                                                                         places: cluster.pins.count))
                .accessibilityIdentifier("map.photoCluster")
            }
        }
        ForEach(model.officialPins) { pin in
            Annotation(pin.name, coordinate: CLLocationCoordinate2D(latitude: pin.coords.lat,
                                                                      longitude: pin.coords.lng)) {
                Button {
                    selectedOfficial = pin
                    selected = nil
                    chosenPlace = nil
                } label: {
                    // 印は 32〜40pt のまま、押せる範囲だけ 44pt に広げる（中心は変わらない）
                    officialMarker(pin)
                        .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // 読み上げでも下書きだと分かるように（画面の札と同じ語）
                .accessibilityLabel(pin.isDraft ? L("\(pin.name)（下書き）", "\(pin.name) (draft)") : pin.name)
            }
        }
    }

    /// 撮影スポットの印。見た目は `SpotMapMarker`（「行きたい場所」の地図と同じ部品）。
    /// 写真の出典は札（`officialCard`）に出す
    private func officialMarker(_ pin: OfficialPins.Pin) -> some View {
        SpotMapMarker(photoURL: pin.photo?.url)
    }

    /// 見えている範囲を控えるだけ。**絞るのはボタンを押したとき**
    private func cameraChanged(_ context: MapCameraUpdateContext) {
        let visible = MapFraming.Frame(
            latitude: context.region.center.latitude,
            longitude: context.region.center.longitude,
            latitudeSpan: context.region.span.latitudeDelta,
            longitudeSpan: context.region.span.longitudeDelta
        )
        model.update(visible: visible)
        zoomChain.observe(visible)
        // 指で地図を触ったら「近くに写真はありません」を下げる（ずらす・つまむ・回す
        // のどれでも。つまんだだけで現在地を見たままでも下げる——地図を自分で見始めた合図）。
        // こちらが寄せた回（現在地を追う・全体へ寄せる・拡大縮小のボタン）は下げない
        noneNearbyBanner.cameraMoved(byUser: camera.positionedByUser)
        // 指で動かしたら、あとから語の当たりへも写真の範囲へも引き戻さない
        // （現在地が無いまま読み込みの間に寄せた回、読み終えて写真の範囲へ戻り、札も消えていた）
        if camera.positionedByUser {
            queryFraming.userMovedCamera()
            framedToPhotos = true
        }
    }

    /// 地図の上に1行。**空の状態を隠さない**——ピンが消えただけの画面にしない
    @ViewBuilder
    private var statusLine: some View {
        if let message = emptyMessage {
            statusCapsule(message, retry: message == Self.loadFailedText)
        } else if let note = locationNote ?? loadFailedNote {
            statusCapsule(note, retry: note == Self.loadFailedText)
        } else if !noneNearbyBanner.dismissed, model.areaFrame == nil, !model.isFiltering,
                  model.frame != nil, let here,
                  NearbyPhotos.noneNearby(model.photos, here: here) {
            // **現在地のまわりに写真が無い**ときの出口。押すと写真全体に寄せる
            // （現在地を追うのはやめる。現在地のボタンでいつでも戻れる）。
            // - 現在地の様子（探しています・取れませんでした）が先。押した回の答えを隠さない
            // - 絞り込み中は出さない（絞ると地図はもう残ったピンへ寄っている）
            // - 寄せる先が無ければ出さない（押しても動かないボタンにしない）
            Button {
                noneNearbyBanner.showedAll()
                frame(model.frame)
            } label: {
                HStack(spacing: 6) {
                    Text(L("近くに写真はありません", "No photos nearby"))
                    Text("·").accessibilityHidden(true)
                    Text(L("全体を見る", "Show all")).font(.subheadline.weight(.semibold))
                }
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(WebTheme.foreground)
                .padding(.horizontal, 14)
                .frame(minHeight: WebTheme.minTapTarget)
                .background(Color.black.opacity(0.7), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            // 右上の操作列（上から 56pt）と縦に重ならないよう、上は 8pt（下端 52pt）
            .padding(.top, 8)
            .accessibilityIdentifier("map.showAll")
        }
    }

    /// 「無い」と「見つからない」を分ける。**スポットのピンが1本でも出ていれば
    /// 帯は出さない**（名前で絞ってスポットだけ当たった回に、ピンの上に
    /// 「見つかりませんでした」が乗っていた）
    private var emptyMessage: String? {
        guard model.hasNothingToShow else { return nil }
        // 地図は画面に戻るたびに読み直す（`.task`）ので、案内はそれを言う
        if model.loadFailed && model.photos.isEmpty {
            return Self.loadFailedText
        }
        if model.isFiltering {
            return L("見つかりませんでした", "No results")
        }
        return L("撮影地の分かる写真がありません", "No photos with a place yet")
    }

    /// 🔴 **読めなかった回は「もう一度試す」を添える**（以前は「開き直すと読み直します」と
    /// 言うだけで、押して読み直す出口が無かった。2026-10-02 の調査）
    private static var loadFailedText: String {
        L("写真を読み込めませんでした", "Couldn't load photos")
    }

    /// リストが空のときに何と言うか
    enum ListEmpty: Equatable {
        /// 写真を読めなかった（警告と「もう一度試す」）
        case failed
        /// 絞り込んで当たらなかった
        case noResults
        /// 読めたが撮影地の分かる写真が無い
        case noPlaces
    }

    /// リストが空の理由。**読めなかったのを「無い」と言わない**——前に読めた写真が
    /// 手元に残っている回は数が本物なので「無い」側（帯の知らせと同じ `photos.isEmpty`）
    nonisolated static func listEmpty(loadFailed: Bool, photosEmpty: Bool, filtering: Bool) -> ListEmpty {
        if loadFailed && photosEmpty { return .failed }
        return filtering ? .noResults : .noPlaces
    }

    /// 写真を読み直す（「もう一度試す」）
    private func retryLoad() {
        // 読んでいる最中は重ねない（ボタンも止めている。古い回の答えは模型が捨てる）
        guard !model.isLoading else { return }
        Task { await model.load(environment: environment) }
    }

    /// 地図の上の帯1本。`retry` なら右に「もう一度試す」
    private func statusCapsule(_ text: String, retry: Bool) -> some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(WebTheme.foreground)
            if retry {
                // 当たりは**ラベルの中で** 44pt に（ボタンの外の余白は押せない）
                Button { retryLoad() } label: {
                    Text(Labels.Common.retry)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.foreground)
                        .frame(minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.isLoading)
                .opacity(model.isLoading ? 0.4 : 1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, retry ? 0 : 8)
        .background(Color.black.opacity(0.7), in: Capsule())
        .padding(.top, 12)
    }

    /// リスト・札の中の「読めなかった」と「もう一度試す」
    private var loadFailedListNote: some View {
        HStack(spacing: 8) {
            listNote(Self.loadFailedText)
            RetryButton(isBusy: model.isLoading, compact: true) { retryLoad() }
        }
    }

    /// 🔴 **撮影スポットのピンだけ出ている回も、写真が取れなかったことを言う**
    /// （ピンがあるので `emptyMessage` は黙り、写真が無いことを誰も言わなかった）。
    ///
    /// **地図の上の帯だけに出す。** リスト（`listArea`）は県ごとのまとまりで、
    /// 写真が取れなくても撮影スポットの行は出る（そちらには混ぜない）。
    /// 現在地の様子（`locationNote`）より後に置く
    private var loadFailedNote: String? {
        guard model.loaded, model.loadFailed, model.photos.isEmpty, !model.hasNothingToShow else { return nil }
        return Self.loadFailedText
    }

    /// 現在地の様子。**取れる前・拒否・失敗を言葉にする**（黙って何も起きない状態にしない）。
    /// ただし拒否・失敗は**ボタンを押した回だけ**——開いたときの自動の回は、
    /// 写真に合わせた地図がそのまま答えになる（断った人に毎回出さない）
    private var locationNote: String? {
        switch location.state {
        case .idle, .located: return nil
        case .asking, .locating: return L("現在地を探しています…", "Finding your location…")
        case .denied:
            guard location.requestedByUser else { return nil }
            return L("位置情報が許可されていません（設定で変更できます）",
                     "Location access is off (you can change it in Settings)")
        case .failed:
            guard location.requestedByUser else { return nil }
            return L("現在地を取れませんでした", "Couldn't get your location")
        }
    }

    /// 「このエリアを検索」。適用中は**数えた結果**と解除の口に変わる
    @ViewBuilder
    private var areaControl: some View {
        if model.areaFrame != nil {
            Button {
                model.clearArea()
            } label: {
                HStack(spacing: 6) {
                    Text(PhotoMapViewModel.areaCountLabel(photos: model.shown.count, places: model.pins.count))
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WebTheme.accentText)
                .padding(.horizontal, 14)
                .frame(minHeight: WebTheme.minTapTarget)
                .background(WebTheme.accentBackground, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("範囲の絞り込みを解除", "Clear area filter"))
        } else {
            Button {
                model.applyArea()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    Text(L("このエリアを検索", "Search this area"))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WebTheme.foreground)
                .padding(.horizontal, 14)
                .frame(minHeight: WebTheme.minTapTarget)
                .background(Color.black.opacity(0.7), in: Capsule())
                .overlay(Capsule().strokeBorder(WebTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            // 範囲がまだ届いていない間は押せない（何も起きないボタンにしない）
            .disabled(!model.canSearchArea)
        }
    }

    /// 地図の操作（モック3-4）。方位磁針・現在地・拡大・縮小を縦に重ねる。
    ///
    /// **方位磁針もこの列に入れる。** 既定のままだと iOS が右上に置き、
    /// この列と重なった（実機の絵・2026-09-25）
    private var mapControls: some View {
        VStack(spacing: WebTheme.mapControlSpacing) {
            // **常に出す。** 北向きの間だけ消えると列が1段詰まり、
            // 回したとき（現在地の2回目）に＋−の位置が1段ずれて、
            // 同じ所を叩いても別のボタンに当たる
            MapCompass(scope: mapScope)
                .mapControlVisibility(.visible)
            locateButton
            VStack(spacing: WebTheme.mapControlSpacing) {
                zoomButton(systemImage: "plus", factor: 1 / MapFraming.zoomStep,
                           label: L("拡大", "Zoom in"))
                zoomButton(systemImage: "minus", factor: MapFraming.zoomStep,
                           label: L("縮小", "Zoom out"))
            }
            // **＋と−の間の隙間は地図へ素通しさせない**（現在地と＋の間は
            // 素通しする——外の列には方位磁針が入っている）。素通しすると、
            // −を狙って隙間を2回叩いたとき地図のダブルタップ（＝拡大）になる。
            // 方位磁針（中身は UIKit）には掛けない——親の手振りと取り合わせない
            .contentShape(Rectangle())
            .onTapGesture {}
        }
    }

    /// **いま見えている枠から数える。** `camera` は `.automatic` のことも
    /// あるので読めない——見えている枠は `onMapCameraChange` が控えている。
    /// 続けて押したときは `ZoomChain` が前に頼んだ枠を土台にする。
    ///
    /// **丸ごと押せるようにする（`contentShape`）。** `.plain` のボタンは
    /// 描いた所しか当たらないので、以前は**記号の線だけ**が押せた——
    /// −は横棒1本ぶんの高さしか無く、外れた指は下の地図に届いていた
    /// （owner の「押すと少し変」・2026-09-25）。
    /// 現在地のボタンと同じ丸にして、1つずつ離して置く
    private func zoomButton(systemImage: String, factor: Double, label: String) -> some View {
        Button {
            move(to: zoomChain.step(from: model.visibleFrame, by: factor))
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(WebTheme.foreground)
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .background(Color.black.opacity(0.7), in: Circle())
                .overlay(Circle().strokeBorder(WebTheme.border, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// 近くの写真へ。**現在地は端末の中だけ**（送らない・残さない）
    private var nearbyButton: some View {
        Button {
            showNearby = true
        } label: {
            Label(L("近くの写真", "Photos near me"), systemImage: "location.magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                // 押せる高さ 44pt。隣の範囲の札（`areaControl`）と同じ作りにして高さをそろえる
                // （以前は上下 10 の余白で約38pt）
                .frame(minHeight: WebTheme.minTapTarget)
                .background(WebTheme.accentBackground, in: Capsule())
                .foregroundStyle(WebTheme.accentText)
        }
        .buttonStyle(.plain)
    }

    /// 現在地。押すたびに**普通の地図アプリと同じ3段**で切り替わる:
    ///
    ///     location                 → 現在地へ寄せて、自分を追う
    ///     location.fill（追っている）→ 向いている方向に地図を回す
    ///     location.north.line.fill → 回すのをやめる（追うのは続ける）
    ///
    /// 指で地図を動かすと MapKit が追うのをやめ、最初の段に戻る。
    /// 位置は**保存も送信もしない**（地図に描くだけ）
    private var locateButton: some View {
        Button {
            zoomChain.reset()
            // 控えは元の控えを引き継ぐ（押すたびに入れ子を深くしない）
            let fallback = camera.fallbackPosition ?? camera
            if camera.followsUserHeading {
                camera = .userLocation(fallback: fallback)
            } else if camera.followsUserLocation {
                camera = .userLocation(followsHeading: true, fallback: fallback)
            } else {
                location.locate()
            }
        } label: {
            Image(systemName: locateSymbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(WebTheme.foreground)
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .background(Color.black.opacity(0.7), in: Circle())
                .overlay(Circle().strokeBorder(WebTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(locateLabel)
    }

    private var locateSymbol: String {
        if camera.followsUserHeading { return "location.north.line.fill" }
        if camera.followsUserLocation { return "location.fill" }
        return "location"
    }

    private var locateLabel: String {
        if camera.followsUserHeading { return L("向きに合わせるのをやめる", "Stop following heading") }
        if camera.followsUserLocation { return L("向いている方向に合わせる", "Follow my heading") }
        return L("現在地へ", "Go to my location")
    }

    /// 押したピンの札:
    ///
    ///     ┌──┐ 日本・宮城県
    ///     │📷│ この周辺の写真 12枚
    ///     └──┘ 写真を見る →   詳細を見る（台帳にあるときだけ）
    private func pinCard(_ pin: MapPin) -> some View {
        // **撮影地を地点として引く。** 名前の無いピンには出さない。
        // 1枚だけの地点も出さない——その写真の個別ページと中身が同じになる
        let spotPlace: DerivedSpot.Place? = {
            guard pin.hasPlaceName else { return nil }
            return DerivedSpot.openable(pin.title, in: model.photos)
        }()
        return HStack(alignment: .top, spacing: 12) {
            RemoteImage(url: pin.photos.first?.gridImageURL,
                        alignment: pin.photos.first?.gridAlignment ?? .center)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(pin.hasPlaceName ? pin.title : L("場所の名前なし", "No place name"))
                    .font(.headline)
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(1)
                Text(PhotoMapViewModel.nearbyCountLabel(pin.photos.count))
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.faint)
                // 何が写っているかの見本（モック3-3）。**3枚まで＋残りの数**
                // ——数は数えた値。押すと一覧へ（下のボタンと同じ行き先）
                if pin.photos.count > 1 {
                    Button {
                        listing = pin
                    } label: {
                        HStack(spacing: 4) {
                            ForEach(pin.photos.prefix(3)) { photo in
                                RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
                                    .frame(width: 36, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            if pin.photos.count > 3 {
                                Text("+\(pin.photos.count - 3)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(WebTheme.muted2)
                                    .frame(width: 36, height: 36)
                                    .background(WebTheme.raised, in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .frame(minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    // 見本は 36pt のまま、押せる高さだけ 44pt。張り出し（上下 4pt）は並びの上で詰める
                    // ——下の「写真を見る」との間（spacing 4）に収まり、重ならない
                    .padding(.vertical, -(WebTheme.minTapTarget - 36) / 2)
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("この場所の写真を見る", "See photos here"))
                }

                Button {
                    listing = pin
                } label: {
                    Text(L("写真を見る →", "See photos →"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.foreground)
                        .frame(minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // **撮影地を地点として開く。** 台帳（`OfficialSpot`）は
                // ここでは引かない——写真のピンは撮影地の文字列の話で、
                // 台帳のスポットは自分のピン（`officialCard`）から開く。
                // 名前の無いピン・1枚だけの地点には出さない
                if let place = spotPlace {
                    NavigationLink {
                        SpotDetailView(spot: place, photos: model.photos)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                            Text(L("\(place.label) の詳細を見る", "About \(place.label)"))
                            Image(systemName: "chevron.right").font(.caption2)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.foreground)
                        .frame(minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            Button {
                selected = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WebTheme.muted2)
                    .webTappable()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Labels.Common.close)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .accessibilityIdentifier("map.pinCard")
    }

    /// 押した撮影スポット（台帳）の札。地点の札（`placeCard`）と同じ並び:
    ///
    ///     ◎ 高屋神社                                 ✕
    ///       香川県 · 観音寺市  下書き
    ///     [ 経路 ]  [ スポットを見る ]
    ///
    /// 「経路」は端末の地図アプリ（`SpotScreen.mapURL`）。「スポットを見る」は
    /// モック13の画面（`OfficialSpotView`）。**「公式」とは書かない**——
    /// 索引の全件が運営未確認の下書きなので、その語を札に置く
    private func officialCard(_ pin: OfficialPins.Pin) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // **写真があれば札の頭に大きく**（ピンの丸 40pt だけでは何の場所か
            // 分からない・owner の指摘 2026-09-26）。出典は下の名前の行に出す
            if let photo = pin.photo {
                Color.clear
                    .frame(height: 150)
                    .overlay(RemoteImage(url: photo.url))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
            }
            HStack(alignment: .top, spacing: 12) {
                officialMarker(pin)
                VStack(alignment: .leading, spacing: 4) {
                    Text(pin.name)
                        .font(.headline)
                        .foregroundStyle(WebTheme.foreground)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        if let region = pin.regionLabel {
                            Text(region)
                                .font(.subheadline)
                                .foregroundStyle(WebTheme.faint)
                                .lineLimit(1)
                        }
                        if pin.isDraft {
                            Text(L("下書き", "Draft"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(WebTheme.muted2)
                                .webChip()
                        }
                    }
                    // **出典は写真と必ず一緒に**（CC BY・CC BY-SA の条件）
                    // 押すと作者は出典のページへ・ライセンスは文面へ（`SpotImageCredit`）
                    if let photo = pin.photo {
                        SpotImageCredit(photo: photo)
                            .font(.caption)
                            .foregroundStyle(WebTheme.muted2)
                            .lineLimit(1)
                            // 長い作者名で**ライセンスを消さない**（末尾から切ると
                            // 「/ CC BY-SA」がまるごと落ちる）。作者の中ほどを削る
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                Button {
                    selectedOfficial = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WebTheme.muted2)
                        .webTappable()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Labels.Common.close)
            }

            HStack(spacing: 8) {
                // **地点の札の「経路」と同じ挙動**（Apple の地図で経路を出す）。
                // 同じ語で片方だけ「地点を表示」にしない
                Button {
                    openDirections(to: pin)
                } label: {
                    Label(L("経路", "Directions"), systemImage: "arrow.triangle.turn.up.right.diamond")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.accentText)
                        .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                        .background(WebTheme.foreground, in: Capsule())
                }
                .buttonStyle(.plain)
                if let spot = model.officialSpot(for: pin) {
                    NavigationLink {
                        OfficialSpotView(spot: spot, spots: model.officialSpots, photos: model.photos,
                                         photosKnown: SpotScreen.photosKnown(loadFailed: model.loadFailed || !model.loaded, photos: model.photos))
                    } label: {
                        Label(L("スポットを見る", "See spot"), systemImage: "mappin.and.ellipse")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WebTheme.foreground)
                            .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                            .overlay(Capsule().strokeBorder(WebTheme.border, lineWidth: 1))
                            // `.plain` は字と縁の線の上だけが当たる——枠の中ぜんぶを押せるように
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("map.officialCard.open")
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .accessibilityIdentifier("map.officialCard")
    }

    /// 撮影スポットへの経路を Apple の地図で開く。`placeCard` と同じ
    /// `directions` の起動指定で渡す。
    ///
    /// 🔴 **索引の座標は約1km に丸めてある**（丸める前の値は台帳にも無い）。
    /// そのまま渡すと最大0.7km ずれた道の上へ案内するので、**スポット名で
    /// Apple の地点（施設だけ・町の中心は拾わない）を探し直し、丸めた座標の近く
    /// （`directionsMatchKm`）のものを行き先にする**（`PlaceSelectableMap.lookUp` と
    /// 同じ拾い直し）。見つからない・`directionsTimeout` 秒で返らなければ、
    /// 丸めた座標にスポット名を付けて渡す。
    ///
    /// **開く直前に、押した札がまだ出ているかを確かめる**——検索の間に札を
    /// 閉じた・別のスポットへ移った・画面を離れたのに地図アプリが開くと、
    /// 押していないものが開いたように見える
    private func openDirections(to pin: OfficialPins.Pin) {
        directionsTask?.cancel()
        directionsTask = Task {
            let item = await SpotDirections.item(name: pin.name, coords: pin.coords)
            // 🔴 **札がいま見えているかまで見る。** 引いてピンが消えた（`selectedOfficial` は
            // 残る）・「スポット」「リスト」へ移った回にも、地図アプリが開いていた
            guard !Task.isCancelled, isOnScreen, model.mode == .map,
                  selectedOfficial?.spotId == pin.spotId,
                  model.showsCard(official: selectedOfficial, onScreen: isOnScreen) else { return }
            item.openInMaps(launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault
            ])
        }
    }

    /// 押した地点の札（デザイン 04b）:
    ///
    ///     金沢21世紀美術館                         ✕
    ///     [ 経路 ]  [ 場所の詳細 ]
    ///     この付近で撮られた写真 12枚     スポットを見る
    ///     ┌──┐┌──┐┌──┐┌──┐ →
    ///
    /// 「経路」「場所の詳細」は Apple の地点情報（MKMapItem）が引けてから押せる。
    /// 写真は**手元の写真から数えたもの**（`PlacePhotos`）。
    private func placeCard(_ place: ChosenPlace) -> some View {
        let photos = PlacePhotos.photos(model.photos, name: place.name, at: place.coords)
        // **名前がそのまま撮影地になっている地点だけ**スポットとして開く。
        // 付近の写真の撮影地から当て推量で選ばない
        let spot = DerivedSpot.openable(place.name, in: model.photos)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(place.name)
                    .font(.headline)
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(2)
                Spacer()
                Button {
                    chosenPlace = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WebTheme.muted2)
                        .webTappable()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Labels.Common.close)
            }

            placeInfo(place)

            HStack(spacing: 8) {
                Button {
                    place.mapItem?.openInMaps(launchOptions: [
                        MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault
                    ])
                } label: {
                    Label(L("経路", "Directions"), systemImage: "arrow.triangle.turn.up.right.diamond")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.accentText)
                        .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                        .background(WebTheme.foreground, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(place.mapItem == nil)
                Button {
                    placeDetail = place.detailItem
                } label: {
                    Label(L("場所の詳細", "Details"), systemImage: "info.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.foreground)
                        .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                        .overlay(Capsule().strokeBorder(WebTheme.border, lineWidth: 1))
                        // `.plain` は字と縁の線の上だけが当たる——枠の中ぜんぶを押せるように
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                // 座標だけの地点では出さない（中身の無い詳細カードになる）
                .disabled(place.detailItem == nil)
                .opacity(place.detailItem == nil ? 0.5 : 1)
            }
            .opacity(place.isLoading ? 0.5 : 1)

            placePhotos(photos, spot: spot)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .accessibilityIdentifier("map.placeCard")
    }

    /// 地点の中身（住所・電話・Web）。**引けたものだけ出す**。
    ///
    /// 以前は名前しか出ず、中身は「場所の詳細」を開かないと見えなかった。
    /// その詳細も地点情報が引けないと押せないままで、owner には
    /// 「押しても中身が見えない」と映った（2026-09-25）
    @ViewBuilder
    private func placeInfo(_ place: ChosenPlace) -> some View {
        switch place.lookup {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text(L("場所の情報を読み込んでいます", "Loading place info"))
                    .font(.footnote)
                    .foregroundStyle(WebTheme.muted2)
            }
        case .coordinateOnly:
            Text(L("Apple のマップにこの場所の詳しい情報がありませんでした。経路は出せます。",
                   "Apple Maps has no details for this place. Directions still work."))
                .font(.footnote)
                .foregroundStyle(WebTheme.muted2)
                .fixedSize(horizontal: false, vertical: true)
        case .found(let item):
            VStack(alignment: .leading, spacing: 6) {
                if let address = item.placemark.title, !address.isEmpty {
                    Label(address, systemImage: "mappin.and.ellipse")
                        .font(.footnote)
                        .foregroundStyle(WebTheme.muted2)
                        .lineLimit(2)
                }
                HStack(spacing: 16) {
                    if let phone = item.phoneNumber, !phone.isEmpty,
                       let tel = URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" }) {
                        Link(destination: tel) {
                            Label(phone, systemImage: "phone")
                                .font(.footnote)
                                .frame(minHeight: WebTheme.minTapTarget)
                        }
                    }
                    if let site = item.url {
                        Link(destination: site) {
                            Label(L("Webサイト", "Website"), systemImage: "safari")
                                .font(.footnote)
                                .frame(minHeight: WebTheme.minTapTarget)
                        }
                    }
                }
                .foregroundStyle(WebTheme.foreground)
            }
        }
    }

    /// 札の写真の段。**「読めていない」と「無い」を分ける**（`NearbyPhotosSheet` と同じ）
    @ViewBuilder
    private func placePhotos(_ photos: [Photo], spot: DerivedSpot.Place?) -> some View {
        if !model.loaded {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
        } else if photos.isEmpty, model.loadFailed, model.photos.isEmpty {
            // 🔴 **読めなかったのに「まだありません」と言わない**（投稿を勧めていた）
            HStack(spacing: 8) {
                Text(Self.loadFailedText)
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.muted2)
                Spacer(minLength: 0)
                RetryButton(isBusy: model.isLoading) { retryLoad() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if photos.isEmpty {
            HStack(spacing: 8) {
                Text(L("この付近の写真はまだありません", "No photos near here yet"))
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.muted2)
                Spacer(minLength: 8)
                Button(action: onPost) {
                    Text(L("写真を投稿する", "Post a photo"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.foreground)
                        .frame(minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(L("この付近で撮られた写真", "Photos taken near here"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.foreground)
                    Text(PhotoMapViewModel.photoCountLabel(photos.count))
                        .font(.caption)
                        .foregroundStyle(WebTheme.muted2)
                    Spacer(minLength: 8)
                    if let spot {
                        NavigationLink {
                            SpotDetailView(spot: spot, photos: model.photos)
                        } label: {
                            Text(L("スポットを見る", "See spot"))
                                .font(.subheadline)
                                .foregroundStyle(WebTheme.muted2)
                                .frame(minHeight: WebTheme.minTapTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 6) {
                        ForEach(photos) { photo in
                            NavigationLink {
                                PhotoDetailView(photo: photo, context: photos)
                            } label: {
                                RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
                                    .frame(width: 72, height: 90)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L("写真を開く", "Open photo"))
                        }
                    }
                }
                .frame(height: 90)
            }
        }
    }


    // MARK: - スポット（板 04c 案A）

    /// 撮影スポットを近い順に（`OfficialSpotList`）。起点は現在地、無ければ地図の中心
    @ViewBuilder
    private var spotsArea: some View {
        let center = here ?? model.visibleFrame.map { Photo.Coords(lat: $0.latitude, lng: $0.longitude) }
        // 上の欄（「撮影地・スポット名で絞る」）で打った語は、地図のピンと同じく名前で当てる
        let spots = MapSearch.fold(model.query).isEmpty
            ? model.officialSpots
            : OfficialSpotIndex.matches(model.officialSpots, query: model.query, aliases: model.spotAliases)
        let rows = OfficialSpotList.rows(spots, photos: model.photos, from: center)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // 板: 12px・medium・白60%。起点が何かを言う（現在地か地図の中心か）
                Text(spotsHeading(hasHere: here != nil, hasCenter: center != nil))
                    .font(.caption.weight(.medium))
                    .tracking(0.5)
                    .foregroundStyle(WebTheme.faint)
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)
                // 写真が読めなかった回は、各行の「写真 0枚」が本当の0ではないと言う
                // （「リスト」の札は `listNotes` で言っていた）
                // （前に読めた写真が手元に残っている回は数が本物なので言わない——
                // 他の知らせと同じく `model.photos.isEmpty` まで見る）
                if model.loadFailed, model.photos.isEmpty {
                    loadFailedListNote
                }
                if model.officialIndexState == .loading {
                    // **読み込み中に「無い」と言わない**
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else if model.officialIndexState == .failed {
                    VStack(spacing: 8) {
                        Text(L("撮影スポットを読み込めませんでした", "Couldn't load photo spots"))
                            .font(.subheadline)
                            .foregroundStyle(WebTheme.faint)
                        RetryButton(isBusy: model.isLoading) { retryLoad() }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else if rows.isEmpty {
                    Text(MapSearch.fold(model.query).isEmpty
                         ? L("公開中の撮影スポットはまだありません", "No photo spots yet")
                         : L("見つかりませんでした", "No results"))
                        .font(.subheadline)
                        .foregroundStyle(WebTheme.faint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    // **Lazy にする。** 一覧は全件（公開済み364件・写真つき315件）で、
                    // 素の VStack だと開いた瞬間に全行の写真（960px・計約31MB）を一斉に
                    // 取りに行き、回線の細い端末では上の行まで時間切れで「読めない」の
                    // 記号になっていた（owner の実機の絵・2026-09-28）
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            NavigationLink {
                                OfficialSpotView(spot: row.spot, spots: model.officialSpots, photos: model.photos,
                                                 photosKnown: SpotScreen.photosKnown(loadFailed: model.loadFailed || !model.loaded, photos: model.photos))
                            } label: {
                                spotRow(row, divider: index > 0)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("map.spotRow")
                        }
                    }
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                // 読み終えたときだけ件数を言う（読み込み中・失敗の「0件」は事実と違う）
                if model.officialIndexState == .ready {
                // **「運営が確かめた」とは書かない**——公開済みには AI 照合で出した行も
                // 含まれ、人の確認（`verifiedBy`）とは別の印（photo-gallery の CLAUDE.md）
                Text(L("公開中の撮影スポットだけ（いまは\(rows.count)件）。",
                       "Published photo spots only (\(rows.count) now)."))
                    .font(.caption)
                    .lineSpacing(3)
                    .foregroundStyle(WebTheme.faint)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private func spotsHeading(hasHere: Bool, hasCenter: Bool) -> String {
        if hasHere { return L("撮影スポット · 近い順", "Photo spots · nearest first") }
        if hasCenter { return L("撮影スポット · 地図の中心から近い順", "Photo spots · nearest to the map") }
        return L("撮影スポット", "Photo spots")
    }

    /// 1行（板: 高さ 64・40pt の丸・15px の名前・12px の「0.8km · 写真 N枚」・右に矢印）
    private func spotRow(_ row: OfficialSpotList.Row, divider: Bool) -> some View {
        HStack(spacing: 12) {
            if let photo = row.spot.photo {
                // 写真があれば写真の丸・真鍮の縁（地図のピンと同じ見分け方）
                RemoteImage(url: photo.url)
                    .frame(width: 40, height: 40)
                    .background(WebTheme.accent)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(WebTheme.accent, lineWidth: 2))
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "camera.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WebTheme.accentText)
                    .frame(width: 40, height: 40)
                    .background(WebTheme.accent, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.92), lineWidth: 2))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(row.spot.name)
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(1)
                // 枚数は写真が取れてから（読み込み中・初回の失敗で手元が空なら「0枚」と言わない。
                // 判定はスポットの画面と同じ `SpotScreen.photosKnown`）
                let sub = Self.spotSubline(row, loaded: SpotScreen.photosKnown(loadFailed: model.loadFailed || !model.loaded,
                                                                               photos: model.photos))
                if !sub.isEmpty {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.35))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .overlay(alignment: .top) {
            if divider { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
        }
        .contentShape(Rectangle())
    }

    /// 「約0.8km · 写真 3枚」。距離は**丸めた座標から測るので「約」を付ける**
    /// （`NearbyPhotos.label`）。起点が無ければ距離を出さない。
    /// 写真を読み込む前は枚数を省く（「写真 0枚」と言わない）
    nonisolated static func spotSubline(_ row: OfficialSpotList.Row, loaded: Bool) -> String {
        let distance = row.km.map { NearbyPhotos.label(km: $0) }
        guard loaded else { return distance ?? "" }
        let photos = L("写真 \(row.photoCount)枚", PhotoMapViewModel.photoCountLabel(row.photoCount))
        guard let distance else { return photos }
        return "\(distance) · \(photos)"
    }

    // MARK: - リスト（都道府県ごと）

    /// 撮影スポットと写真を**都道府県ごとのまとまり**にする（`RegionList`・owner の提案 2026-09-28）。
    /// いまいる県（現在地、無ければ地図の中心）を先頭にして開き、ほかの県は閉じて件数だけ。
    /// 県の先頭にその県で撮られた写真を横に並べ（**写真が主役**）、下に撮影スポットの行
    /// （「スポット」の札と同じ行・近い順）。
    ///
    /// 絞り込みは上の欄とカテゴリだけ効かせる。**地図の見えている範囲では切らない**
    /// （全国を県で並べる札なので）。座標の無い写真も「場所が分からない写真」に入る
    @ViewBuilder
    private var listArea: some View {
        let center = here ?? model.visibleFrame.map { Photo.Coords(lat: $0.latitude, lng: $0.longitude) }
        let sections = RegionList.sections(photos: model.photos, spots: model.officialSpots,
                                           query: model.query, category: model.category,
                                           aliases: model.spotAliases, from: center)
        let currentId = sections.first(where: \.isCurrent)?.id
        let filtering = !MapSearch.fold(model.query).isEmpty || model.category != nil
        // **撮影スポットの台帳が届くまでは並べない。** 届く前は県を当てる手がかりが無く、
        // 座標だけの写真が「場所が分からない」に入る。そこから詳細を開いた後に台帳が届くと、
        // 写真が県へ移って元の行が消え、詳細がその場で閉じる（台帳は控えがあればすぐ届く）
        if model.officialIndexState == .loading || (sections.isEmpty && !model.loaded) {
            // **読み込み中に「無い」と言わない**
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            Spacer()
        } else if sections.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                // 写真の失敗は下の帯が言う（二度言わない）。ここでは台帳の失敗だけ
                indexNote
                // **失敗と空を分ける**（`listEmpty`）。空に警告の三角と「もう一度試す」を出さない
                switch Self.listEmpty(loadFailed: model.loadFailed, photosEmpty: model.photos.isEmpty,
                                      filtering: filtering) {
                case .failed:
                    ErrorBanner(message: Self.loadFailedText, isBusy: model.isLoading) { retryLoad() }
                case .noResults:
                    EmptyState(message: L("見つかりませんでした", "No results"))
                case .noPlaces:
                    EmptyState(message: L("撮影地の分かる写真がありません", "No photos with a place yet"))
                }
            }
            .padding(.top, 8)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    listNotes
                    ForEach(sections) { section in
                        regionSection(section)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .onAppear { if let currentId { autoOpenedRegions.insert(currentId) } }
            .onChange(of: currentId) { _, id in if let id { autoOpenedRegions.insert(id) } }
        }
    }

    /// 片方だけ取れていない回の断り書き（リストは取れた方だけで描くので、黙ると
    /// 「写真が無い」「スポットが無い」と読める）
    @ViewBuilder
    private var listNotes: some View {
        if model.loadFailed {
            loadFailedListNote
        }
        indexNote
    }

    @ViewBuilder
    private var indexNote: some View {
        if model.officialIndexState == .failed {
            HStack(spacing: 8) {
                listNote(L("撮影スポットを読み込めませんでした", "Couldn't load photo spots"))
                // 写真も読めていない回は上の行の「もう一度試す」が両方を読み直す（2つ並べない）
                if !model.loadFailed {
                    RetryButton(isBusy: model.isLoading, compact: true) { retryLoad() }
                }
            }
        }
    }

    private func listNote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(WebTheme.faint)
            .padding(.horizontal, 4)
    }

    /// 開いているか。押した県は押したとおり。押していない県は、起点の県（と、これまでに
    /// 起点だった県）だけ開く
    private func isOpen(_ section: RegionList.Section) -> Bool {
        regionOpen[section.id] ?? (section.isCurrent || autoOpenedRegions.contains(section.id))
    }

    private func regionSection(_ section: RegionList.Section) -> some View {
        let open = isOpen(section)
        // **中も Lazy に。** 開いた県の行を一斉に描くと、丸写真を全部同時に取りに行く
        // （「スポット」の札で「読めない」記号になった穴・`spotsArea` の注記）
        return LazyVStack(spacing: 0) {
            Button {
                regionOpen[section.id] = !open
            } label: {
                HStack(spacing: 8) {
                    Text(section.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.foreground)
                    if section.isCurrent {
                        // 現在地が無ければ地図の中心から決めている（「スポット」の札の見出しと同じ言い分け）
                        Text(here != nil ? (section.key.isCountry ? L("いまいる国", "You're here") : L("いまいる県", "You're here"))
                             : L("地図の中心", "Map center"))
                            .font(.caption)
                            .foregroundStyle(WebTheme.faint)
                    }
                    Spacer(minLength: 8)
                    Text(RegionList.countLabel(section))
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WebTheme.faint)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(open ? L("開いている", "Expanded") : L("閉じている", "Collapsed"))
            .accessibilityIdentifier("map.region")
            if open {
                if !section.photos.isEmpty {
                    regionPhotos(section.photos)
                }
                ForEach(section.spots) { row in
                    NavigationLink {
                        OfficialSpotView(spot: row.spot, spots: model.officialSpots, photos: model.photos,
                                         photosKnown: SpotScreen.photosKnown(loadFailed: model.loadFailed || !model.loaded, photos: model.photos))
                    } label: {
                        spotRow(row, divider: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("map.regionSpotRow")
                }
            }
        }
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// その県で撮られた写真を横に並べる（札の写真の列と同じ大きさ）。押すと写真の詳細
    private func regionPhotos(_ photos: [Photo]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 6) {
                ForEach(photos) { photo in
                    NavigationLink {
                        PhotoDetailView(photo: photo, context: photos)
                    } label: {
                        RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
                            .frame(width: 72, height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(photo.accessibilityText)
                }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 90)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }

    // MARK: - カメラ

    /// 人が替わったので読み直す。**札はすぐ下げる**——ここに来るのは地図が
    /// 画面に出ている（札の先へ進んでいない）ときだけで、読み込みを待つ間に
    /// 前の人あての写真を次の人に見せない
    private func reloadForNewUser() {
        loadedUserRevision = hidden.userRevision
        selected = nil
        Task {
            // 集合を自分で渡してから読む（`GalleryView.reloadHidden` と同じ理由）
            await environment.gallery.setHidden(hidden.snapshot)
            await model.load(environment: environment)
            // 読んでいる間に押した札・開いた一覧も、前の人の写しなので差し替える。
            // 一覧のシートを出している間もここを通る（シートでは `onDisappear` が
            // 来ない）ので、シートの中で開いている詳細は、その写真が次の人の一覧に
            // 無ければ閉じ、ピン（座標）ごと無ければシートごと閉じる——前の人あての
            // 写真を見せ続けない向きに倒している
            refreshSelected()
            dropHidden()
        }
    }

    /// 選んでいた札を、読み直したピンに差し替える（札は押した時点の写しなので、
    /// そのままだと前の人あての写真を持ち続ける）。ピンが消えていれば下げる
    private func refreshSelected() {
        selected = PhotoMapViewModel.refreshed(selected, in: model.pins)
        if listing != nil { listing = PhotoMapViewModel.refreshed(listing, in: model.pins) }
    }

    /// 手元のピンからブロック／通報したぶんを落とす。選んでいた札が
    /// 落ちた写真を持っていたら下げる（札は押した時点のピンの写しを持つ）
    private func dropHidden() {
        needsDrop = false
        model.drop(hiddenBy: hidden)
        if let pin = selected, hidden.visible(pin.photos).count != pin.photos.count {
            selected = nil
        }
    }

    /// 地図をその枠へ寄せる。nil なら動かさない（既定に戻して地球儀にしない）
    ///
    /// ＋−の続け押しの控え（`ZoomChain`）は忘れる——ボタン以外で動いた
    private func frame(_ frame: MapFraming.Frame?) {
        zoomChain.reset()
        move(to: frame)
    }

    /// 枠へ動かすだけ（＋−から。続け押しの控えは残す）
    private func move(to frame: MapFraming.Frame?) {
        guard let frame else { return }
        camera = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: frame.latitude, longitude: frame.longitude),
            span: MKCoordinateSpan(latitudeDelta: frame.latitudeSpan,
                                   longitudeDelta: frame.longitudeSpan)
        ))
    }
}

struct MapPin: Identifiable, Equatable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String
    let photos: [Photo]

    /// 撮影地の文字列を持つか。無いピンの `title` は仮の語（「撮影地」）で、
    /// 札や一覧のシートではそれを場所の名前として出さない
    var hasPlaceName: Bool {
        photos.contains { !($0.location ?? "").isEmpty }
    }

    static func == (lhs: MapPin, rhs: MapPin) -> Bool { lhs.id == rhs.id }

    /// 同じ座標の写真をまとめる。丸めてあるので、そのまま文字列にして鍵にできる。
    static func group(_ photos: [Photo]) -> [MapPin] {
        var buckets: [String: [Photo]] = [:]
        for photo in photos {
            guard let coords = photo.coords else { continue }
            let key = "\(coords.lat),\(coords.lng)"
            buckets[key, default: []].append(photo)
        }
        return buckets.compactMap { key, photos in
            guard let coords = photos.first?.coords else { return nil }
            let title = photos.first(where: { !($0.location ?? "").isEmpty })?.location ?? L("撮影地", "Place")
            return MapPin(
                id: key,
                coordinate: CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lng),
                title: title,
                photos: photos
            )
        }
        .sorted { $0.id < $1.id }
    }
}
