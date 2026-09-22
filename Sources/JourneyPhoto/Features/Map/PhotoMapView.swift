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

    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var model = PhotoMapViewModel()
    @StateObject private var location = CurrentLocation()
    /// 押したピン。**下の札に出す**（シートで画面を覆うと地図が見えない）
    @State private var selected: MapPin?
    /// 一覧を開くとき（札の「写真を見る →」・リストの行）
    @State private var listing: MapPin?
    /// 地図の見ている場所。**写真に合わせてから開く**（指示書 9-2）
    @State private var camera: MapCameraPosition = .automatic

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
        .navigationTitle(Labels.Navigation.map)
        .navigationBarTitleDisplayMode(.inline)
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
        // 現在地が取れたら、そこへ寄せるだけ。**周辺の写真に絞りはしない**
        .onChange(of: location.state) { _, state in
            guard case .located(let latitude, let longitude) = state else { return }
            frame(MapFraming.Frame(latitude: latitude, longitude: longitude,
                                   latitudeSpan: 0.05, longitudeSpan: 0.05))
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
    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
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
        Map(position: $camera) {
            ForEach(model.pins) { pin in
                Annotation(pin.title, coordinate: pin.coordinate) {
                    Button {
                        selected = pin
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
        // 見えている範囲を控えるだけ。**絞るのはボタンを押したとき**
        .onMapCameraChange(frequency: .onEnd) { context in
            model.update(visible: MapFraming.Frame(
                latitude: context.region.center.latitude,
                longitude: context.region.center.longitude,
                latitudeSpan: context.region.span.latitudeDelta,
                longitudeSpan: context.region.span.longitudeDelta
            ))
        }
        .overlay(alignment: .top) { statusLine }
        .overlay(alignment: .topLeading) {
            areaControl
                .padding(.leading, 16)
                .padding(.top, 56)
        }
        .overlay(alignment: .topTrailing) {
            locateButton
                .padding(.trailing, 16)
                .padding(.top, 56)
        }
        // 押したピンの札。**地図を覆わない**ので、押したまま周りを見られる
        .overlay(alignment: .bottom) {
            // **消えたピンの札は出さない。** 絞り込みを変えるとピンは
            // 入れ替わるが、札は値の写しなので残ってしまう
            if let selected, model.stillShown(selected) {
                pinCard(selected)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
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
        let spots = model.spots(for: pin)
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
                // 台帳に実在するスポットにだけ導線を出す。無ければ何も置かない
                // （「spotId はあるが台帳に無い」で空の詳細に落とさない）
                ForEach(spots) { spot in
                    NavigationLink {
                        SpotDetailView(spot: spot, photos: model.photos, ledger: model.spots)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                            Text(L("\(spot.name) の詳細を見る", "About \(spot.name)"))
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
