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
    var avatarURL: URL?
    var onOpenNotifications: () -> Void = {}
    /// 投稿の入口（`RootView` の2択）。地点に写真が無いときの「写真を投稿する」から開く
    var onPost: () -> Void = {}

    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var model = PhotoMapViewModel()
    @StateObject private var location = CurrentLocation()
    /// 取れた現在地。**この画面が開いている間だけ**持つ
    /// （保存も送信もしない——`CurrentLocation` の約束をここでも守る）
    @State private var here: Photo.Coords?
    @State private var showNearby = false
    /// 押したピン。**下の札に出す**（シートで画面を覆うと地図が見えない）
    @State private var selected: MapPin?
    /// 一覧を開くとき（札の「写真を見る →」・リストの行）
    @State private var listing: MapPin?
    /// 押した地点（Apple の地図が描く POI）。**iOS 18 以降だけ**入る
    /// （`PlaceSelectableMap`）。ピンの札とは同時に出さない
    @State private var chosenPlace: ChosenPlace?
    /// Apple の詳細カードに出す地点（札の「場所の詳細」）
    @State private var placeDetail: MKMapItem?
    /// 地図の見ている場所。**写真に合わせてから開く**（指示書 9-2）
    @State private var camera: MapCameraPosition = .automatic
    /// 拡大・縮小を続けて押したときの土台（`MapFraming.ZoomChain`）
    @State private var zoomChain = MapFraming.ZoomChain()
    /// 方位磁針を地図の外（右の操作列）に置くための名前。
    /// 置かないと、iOS が右上に出す方位磁針が操作列と重なる
    @Namespace private var mapScope

    var body: some View {
        VStack(spacing: 0) {
            searchField
            categoryChips
            modePicker
            if model.mode == .map {
                mapArea
            } else {
                listArea
            }
        }
        .webScreen()
        .navigationTitle("Journey Photo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { AppHeaderItems(unread: unread, avatarURL: avatarURL, onOpenNotifications: onOpenNotifications) }
        .task {
            await model.load(environment: environment)
            frame(model.frame)
        }
        // 絞りが変わったら、残ったピンに寄せ直す（範囲で絞ったときは
        // 見ている場所を動かさない——押した範囲がそのまま答え）
        .onChange(of: model.query) { _, _ in
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
        }
        // 現在地が取れたら、そこへ寄せる。**絞りはしない**——代わりに
        // 「近くの写真」の入口を出す（押すまで何も変えない）
        .onChange(of: location.state) { _, state in
            guard case .located(let latitude, let longitude) = state else { return }
            here = Photo.Coords(lat: latitude, lng: longitude)
            frame(MapFraming.Frame(latitude: latitude, longitude: longitude,
                                   latitudeSpan: 0.05, longitudeSpan: 0.05))
        }
        .sheet(isPresented: $showNearby) {
            if let here {
                NearbyPhotosSheet(center: here, photos: model.photos)
            }
        }
        .sheet(item: $listing) { pin in
            NavigationStack {
                List(pin.photos) { photo in
                    NavigationLink {
                        PhotoDetailView(photo: photo, context: pin.photos)
                    } label: {
                        HStack(spacing: 10) {
                            RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(photo.displayTitle.isEmpty ? (photo.location ?? L("写真", "Photo")) : photo.displayTitle)
                        }
                    }
                }
                .navigationTitle(pin.hasPlaceName ? pin.title : L("場所の名前なし", "No place name"))
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    // MARK: - 絞る口

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
            .padding(.vertical, 10)
        }
    }

    /// 探す画面のチップと同じ形（白地＝選択中）。当たりは上下 11pt ＋ 字で 44pt に届く
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
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 「地図 / リスト」。**どちらも同じ `shown` から描く**
    private var modePicker: some View {
        Picker("", selection: $model.mode) {
            ForEach(PhotoMapViewModel.Mode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
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
                // 入れ替わるが、札は値の写しなので残ってしまう
                if let selected, model.stillShown(selected) {
                    pinCard(selected)
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
        // 地点を選んだら、ピンの札は下げる（札は1枚だけ）
        .onChange(of: chosenPlace) { _, place in
            if place != nil { selected = nil }
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
    @MapContentBuilder
    private var pinMarkers: some MapContent {
        ForEach(model.pins) { pin in
            Annotation(pin.title, coordinate: pin.coordinate) {
                Button {
                    selected = pin
                    chosenPlace = nil
                } label: {
                    ZStack(alignment: .topTrailing) {
                        RemoteImage(url: pin.photos.first?.gridImageURL,
                                    alignment: pin.photos.first?.gridAlignment ?? .center)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        // **数えた枚数**（モックのクラスタの数字にあたる）
                        if pin.photos.count > 1 {
                            Text("\(pin.photos.count)")
                                .font(.caption2.weight(.bold))
                                .padding(4)
                                .background(.thinMaterial, in: Circle())
                                .offset(x: 6, y: -6)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 見えている範囲を控えるだけ。**絞るのはボタンを押したとき**
    private func cameraChanged(_ context: MapCameraUpdateContext) {
        model.update(visible: MapFraming.Frame(
            latitude: context.region.center.latitude,
            longitude: context.region.center.longitude,
            latitudeSpan: context.region.span.latitudeDelta,
            longitudeSpan: context.region.span.longitudeDelta
        ))
    }

    /// 地図の上に1行。**空の状態を隠さない**——ピンが消えただけの画面にしない
    @ViewBuilder
    private var statusLine: some View {
        if let message = emptyMessage {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(WebTheme.foreground)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.7), in: Capsule())
                .padding(.top, 12)
        } else if let note = locationNote {
            Text(note)
                .font(.subheadline)
                .foregroundStyle(WebTheme.foreground)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.7), in: Capsule())
                .padding(.top, 12)
        }
    }

    /// 「無い」と「見つからない」を分ける
    private var emptyMessage: String? {
        guard model.loaded, model.shown.isEmpty else { return nil }
        if model.isFiltering {
            return L("見つかりませんでした", "No results")
        }
        return L("撮影地の分かる写真がありません", "No photos with a place yet")
    }

    /// 現在地の様子。**取れる前・拒否・失敗を言葉にする**（黙って何も起きない状態にしない）
    private var locationNote: String? {
        switch location.state {
        case .idle, .located: return nil
        case .asking, .locating: return L("現在地を探しています…", "Finding your location…")
        case .denied: return L("位置情報が許可されていません（設定で変更できます）",
                               "Location access is off (you can change it in Settings)")
        case .failed: return L("現在地を取れませんでした", "Couldn't get your location")
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
                    Text(L("この範囲の写真 \(model.shown.count)枚・\(model.pins.count)地点",
                           "\(model.shown.count) photos · \(model.pins.count) places here"))
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
    /// この列と重なった（実機の絵・2026-09-25）。方位磁針は北を向いて
    /// いる間は出ない——そのときは現在地のボタンが一番上に来る
    private var mapControls: some View {
        VStack(spacing: WebTheme.mapControlSpacing) {
            MapCompass(scope: mapScope)
            locateButton
            VStack(spacing: WebTheme.mapControlSpacing) {
                zoomButton(systemImage: "plus", factor: 1 / MapFraming.zoomStep,
                           label: L("拡大", "Zoom in"))
                zoomButton(systemImage: "minus", factor: MapFraming.zoomStep,
                           label: L("縮小", "Zoom out"))
            }
            // **＋と−の間の隙間を地図へ素通しさせない。** 素通しすると、
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
            frame(zoomChain.step(from: model.visibleFrame, by: factor))
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
                .padding(.vertical, 10)
                .background(WebTheme.accentBackground, in: Capsule())
                .foregroundStyle(WebTheme.accentText)
        }
        .buttonStyle(.plain)
    }

    /// 現在地。**1回取って寄せるだけ**（追跡も保存もしない）
    private var locateButton: some View {
        Button {
            location.locate()
        } label: {
            Image(systemName: "location")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(WebTheme.foreground)
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .background(Color.black.opacity(0.7), in: Circle())
                .overlay(Circle().strokeBorder(WebTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("現在地へ", "Go to my location"))
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
                Text(L("この周辺の写真 \(pin.photos.count)枚",
                       "\(pin.photos.count) photos nearby"))
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("この場所の写真を見る", "See photos here"))
                }

                Button {
                    listing = pin
                } label: {
                    Text(L("写真を見る →", "See photos →"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.22, green: 0.65, blue: 0.98))
                        .frame(minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // **撮影地を地点として開く。** 台帳は引かない（本番は
                // 台帳を持たない——`DerivedSpot` の注記）。
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
                Button {
                    placeDetail = place.mapItem
                } label: {
                    Label(L("場所の詳細", "Details"), systemImage: "info.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.foreground)
                        .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                        .overlay(Capsule().strokeBorder(WebTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            // 引けるまでは押せない（押しても何も起きないボタンにしない）
            .disabled(place.mapItem == nil)
            .opacity(place.mapItem == nil ? 0.5 : 1)

            placePhotos(photos, spot: spot)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .accessibilityIdentifier("map.placeCard")
    }

    /// 札の写真の段。**「読めていない」と「無い」を分ける**（`NearbyPhotosSheet` と同じ）
    @ViewBuilder
    private func placePhotos(_ photos: [Photo], spot: DerivedSpot.Place?) -> some View {
        if !model.loaded {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
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
                    Text(L("\(photos.count)枚", "\(photos.count) photos"))
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

    // MARK: - リスト

    /// 同じ絞り込みの結果を、**ピンと同じ束ね**で行にする（行の数＝ピンの数）。
    /// 枚数は数えた値。いいね数・保存は出さない（モックにはあるが求められていない）
    @ViewBuilder
    private var listArea: some View {
        if let message = emptyMessage {
            ErrorBanner(message: message)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.pins) { pin in
                        Button {
                            listing = pin
                        } label: {
                            listRow(pin)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private func listRow(_ pin: MapPin) -> some View {
        HStack(spacing: 12) {
            RemoteImage(url: pin.photos.first?.gridImageURL,
                        alignment: pin.photos.first?.gridAlignment ?? .center)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                // 撮影地の文字列が無いピンを「撮影地」という場所に見せない
                Text(pin.hasPlaceName ? pin.title : L("場所の名前なし", "No place name"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(pin.hasPlaceName ? WebTheme.foreground : WebTheme.faint)
                    .lineLimit(1)
                Text(L("\(pin.photos.count)枚", "\(pin.photos.count) photos"))
                    .font(.caption)
                    .foregroundStyle(WebTheme.muted2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(WebTheme.faint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: WebTheme.minTapTarget)
        .contentShape(Rectangle())
    }

    // MARK: - カメラ

    /// 地図をその枠へ寄せる。nil なら動かさない（既定に戻して地球儀にしない）
    private func frame(_ frame: MapFraming.Frame?) {
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
    /// リストや札ではそれを場所の名前として出さない
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
