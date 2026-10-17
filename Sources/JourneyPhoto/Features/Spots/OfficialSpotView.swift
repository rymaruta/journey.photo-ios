import SwiftUI
import MapKit

/// 台帳の撮影スポット（モック13）。
///
/// `SpotDetailView` が**撮影地の集まり**（写真から導く・モック5）を出すのに
/// 対して、こちらは Web の台帳 `content/spots.json` から落ちてきた索引の
/// 1件（`OfficialSpot`）を出す。写真との紐付けは `Photo.spotId` だけで、
/// 今日その写真は0枚——**全節が写真に依存する `SpotDetailView` を広げずに**
/// 別の画面にした。
///
/// 🔴 **下書きを「公式」と名乗らない。** 小見出しと帯で最初にそう言う
/// （`SpotScreen.eyebrow` / `reviewNotice`）。
///
/// **本文（2026-09-27）**: 公開済みの場所だけ、Web が配る本文
/// （`/app/data/spots/<slug>.json`・`SpotBody`）を取りに行き、「この場所の魅力」
/// 「撮影ガイド」の節と、確かめた印の1行（人の確認か、AI 照合の出典）を出す。
/// 印の無い本文は読まない。取れない間（まだ本番に無い・圏外）は節を出さないだけ。
/// アクセス・駐車場・注意点は出さない（確認者つきの出典が要る項目）。
///
/// 並び（板 13・2026-09-27 owner「写真が主役」）: 地図 → 小見出し → 名前 →
/// 地域と枚数 → 帯 → 行動3つ → 概要 → **写真がある場所はこの場所の写真** →
/// 本文の節 → **写真が0枚の場所は「まだありません」** → 近くの撮影スポット → 印の1行。
///
/// **作例（2026-10-03）**: 本文の `samples`（Wikimedia Commons の写真・`SpotSample`）を
/// 「この場所の魅力」と「撮影ガイド」の間に出す（Web の `SpotGuideClient` と同じ位置）。
struct OfficialSpotView: View {

    let spot: OfficialSpot
    /// 「近くの撮影スポット」を引く索引。呼び出し側が持っている一覧をそのまま渡す
    let spots: [OfficialSpot]
    /// 「この場所の写真」を引く公開写真。`spotId` で紐づいたものだけ数える
    let photos: [Photo]
    /// `photos` が公開写真の全部か。**false なら「この場所の写真（0）まだありません」を言わない**
    /// ——写真の一覧を持たない画面（ストーリーの撮影地から開いたとき）が空を渡すと、
    /// 紐づいた写真があっても「まだありません」と事実と違うことを言っていた
    var photosKnown = true

    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var environment: AppEnvironment
    /// 渡された写真は開いた時点の写しなので、ブロック／通報をここで反映する。
    /// **見ている最中には絞らない**（`FavoritesView` の `photos` の注記）——
    /// 押した元の `NavigationLink` が消えると、開いている詳細がその場で閉じ、
    /// 通報の「受け付けました」も見えない。戻ってきたとき（`onAppear`）に絞る
    @EnvironmentObject private var hidden: ModerationStore
    @State private var dropped = ModerationSnapshot()
    /// 戻るスワイプ途中の `onAppear` で写真の格子を消さない印（`FrontConfirm`）
    @State private var front = FrontConfirm()
    @State private var frontSettle: Task<Void, Never>?

    @State private var camera: MapCameraPosition = .automatic
    /// 本文（公開済みの場所だけ取りに行く）。取れなければ nil のまま
    @State private var spotBody: SpotBody?
    /// 詳細を重ねた行（分けた置き場の索引だけの行で開いたとき・2026-10-07）。取れなければ nil のまま
    @State private var detailed: OfficialSpot?
    /// 読み込めなかった作例（出典のページで覚える）。その1枚を出典ごと隠す
    @State private var brokenSamples: Set<URL> = []
    /// Pro かどうか・ログインしているか（「作例を重ねて撮る」の入口）
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var store: StoreService
    /// 「作例を重ねて撮る」（Pro）の撮る画面・Pro の案内・Pro かを確かめている最中
    /// （流れは投稿のシートの入口と同じ部品・`ComposeGuideLauncher`・2026-10-10）
    @StateObject private var composeLauncher = ComposeGuideLauncher()
    /// 「このスポットの写真を投稿」から開く投稿画面
    @State private var showUpload = false
    /// 「作例を重ねて撮る」で撮って「投稿」を押した1枚。撮る画面を閉じきったら投稿画面に入れて開く
    @State private var pendingCapture: CameraCapture?
    /// この画面から投稿した（写真の一覧は開いた時点の写しなので、すぐには並ばない）
    @State private var postedHere = false
    /// 「光の時刻」で見ている日（今日から何日ずらしたか・その土地の暦）
    @State private var lightOffset = 0
    /// 「経路」を探している最中（連打で2つ開かない）・その仕事（頁を離れたら取り消す）
    @State private var openingDirections = false
    @State private var directionsTask: Task<Void, Never>?
    /// 頁が出ているか（「経路」を探している間に離れたら開かない）
    @State private var onScreen = false
    /// 文字サイズ。アクセシビリティの大きさでは「光の時刻」の行を縦に積む
    @Environment(\.dynamicTypeSize) private var typeSize

    /// 写真・概要・下書きの日付を出す行。**索引だけの行で開いたら、詳細を重ねたもの**（`SpotDetailNeeds`）
    private var shown: OfficialSpot { detailed?.spotId == spot.spotId ? detailed! : spot }

    /// **確定した紐づけだけ**（`Photo.spotId`）。撮影地の文字列では当てない
    private var linked: [Photo] { dropped.visible(photos.filter { $0.spotId == spot.spotId }) }

    private var nearby: [(spot: OfficialSpot, km: Double)] {
        OfficialSpotIndex.nearby(spot, in: spots)
    }

    /// 「行きたい」の鍵。**撮影地の鍵と混ぜない**（`SavedSpotKey`）
    private var wishKey: String { SavedSpotKey.official(spot.slug) }

    /// 配る文に入れる地図のリンク。**座標があるときだけ**（`SpotScreen`）。
    /// 頁の「地図で見る」はアプリの中の地図（`OfficialSpotMapView`）で、このリンクは開かない
    private var mapURL: URL? { SpotScreen.mapURL(name: spot.name, coords: spot.coords) }

    /// 配る文。**公開済みのスポットはサイトのページ（`/spots/<slug>`）も入れる**
    /// （Web の本番に `app/spots/[slug]` がある）。下書きはページが無いので入れない
    private var shareText: String {
        SpotScreen.shareText(name: spot.name, region: spot.regionLabel, mapURL: mapURL,
                             pageURL: SpotScreen.pageURL(slug: spot.slug, isDraft: spot.isDraft,
                                                         siteBase: AppConfig.siteBaseURL))
    }

    var body: some View {
        ScrollView {
            // v2（2026-10-14）: 間は 20 で一つにそろえる（板 SpotDetail は頭の段 12・節の間 32。
            // 下書きの帯・説明の帯が節の間に挟まるので、一つの値にした）
            VStack(alignment: .leading, spacing: JPSpace.l) {
                // 写真があれば写真を主役に（板 SpotDetail の 460pt・題は写真の下端に白で）。
                // 無ければ地図と、その下の黒地に題（板 SpotLanding C・眉は真鍮）
                if let photo = shown.photo {
                    heroPhoto(photo)
                } else {
                    heroMap
                    header(onPhoto: false)
                }
                if let notice = SpotScreen.reviewNotice(review: spot.isDraft, draftedAt: shown.draftedAt) {
                    draftNotice(notice)
                }
                actions
                journeyCue
                summary
                // **写真が主役。** 写真がある場所は本文より先に出す
                if !linked.isEmpty { spotPhotos }
                // 光の時刻（計算値・写真が無くても出せる）→ 本文の節。ひとつの並びの上限を越えないようまとめる
                Group {
                    lightSection
                    bodySections
                }
                // 写真が0枚の場所は、本文の後に「まだありません」（1画面目を空にしない）
                // 下の3つはまとめる（ひとつの並びに置ける数の上限を越えないように）
                Group {
                    if linked.isEmpty { spotPhotos }
                    nearbySpots
                    checkLine
                }
            }
            .padding(.bottom, 32)
        }
        .onAppear {
            switch front.appear() {
            case .first:
                landOfficialFront()
            case .returning:
                frontSettle?.cancel()
                frontSettle = Task {
                    try? await Task.sleep(nanoseconds: FrontConfirm.settleNanoseconds)
                    guard !Task.isCancelled, front.confirm() else { return }
                    landOfficialFront()
                }
            }
        }
        .onDisappear {
            frontSettle?.cancel()
            frontSettle = nil
            front.disappear()
            onScreen = false
            directionsTask?.cancel()
        }
        // 下書き→公開に差し替わったら取り直す（slug だけだと走り直さない）
        .task(id: "\(spot.slug)|\(spot.isDraft)") {
            brokenSamples = []
            // 下書きは取りに行かない（本文は公開済みの場所にしか無い）
            guard !spot.isDraft else {
                spotBody = nil
                return
            }
            let fetched = await environment.spots.fetchBody(slug: spot.slug)
            guard !Task.isCancelled else { return }
            spotBody = fetched
        }
        // 索引だけの行で開いたら、その区分の詳細（写真・概要）を重ねる（分けた置き場・2026-10-07）
        .task(id: "\(spot.spotId)|\(spot.isIndexOnly)") {
            guard spot.isIndexOnly else { return }
            let merged = await environment.spots.withDetails([spot], for: [spot]).first
            guard !Task.isCancelled, let merged, !merged.isIndexOnly else { return }
            detailed = merged
        }
        .webScreen()
        .navigationTitle(spot.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                }
                .webToolbarIcon()
                // 絵だけのボタン。名前を明示する（OS 任せにすると版によって読まれ方が揺れる）
                .accessibilityLabel(L("シェア", "Share"))
                // シェアは頁にこの1つだけ（2026-10-11・`SpotScreen.officialActions`）
                .accessibilityIdentifier("spot.official.share")
            }
        }
        .accessibilityIdentifier("spot.official")
    }

    /// 前面が確定したときだけ、写真の格子の写しを取る
    private func landOfficialFront() {
        dropped = hidden.snapshot
        onScreen = true
    }

    // MARK: - 代表写真（Wikimedia Commons・2026-09-26）

    /// 横いっぱいの写真（v2 の板 SpotDetail の 460pt）と、その下に出典の1行。
    /// 写真の下端は黒へ溶かし、題（眉・明朝 32・地域と枚数）を白で載せる（写真の上は白だけ・CLAUDE.md）。
    /// **出典は写真と必ず一緒に**（CC BY・CC BY-SA の条件）。押すと Commons のページへ
    private func heroPhoto(_ photo: SpotImage) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            Color.clear
                .frame(height: Self.heroHeight)
                .overlay(RemoteImage(url: photo.url))
                .clipped()
                // `Color.clear` は読み上げの対象にならないので、1つの画像としてまとめて名前を付ける
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isImage)
                .accessibilityLabel(L("\(spot.name) の写真", "Photo of \(spot.name)"))
                // 下端を黒へ溶かす（板: 下 220pt・黒 4% の位置から透明へ）。題の字を写真から切り離す
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [Color.black.opacity(0), Color.black],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.heroFadeHeight)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .overlay(alignment: .bottomLeading) {
                    header(onPhoto: true)
                        .padding(.bottom, JPSpace.m)
                }
            // 当たりは1行全体で 44pt 以上（2026-10-03・`CreditLink` の注記）。見た目は `SpotImageCredit` のまま
            CreditLinksMenu(links: photo.creditLinks, accessibilityLabel: photo.credit, alignment: .topTrailing) {
                SpotImageCredit(photo: photo)
                    .font(.caption)
                    .foregroundStyle(WebTheme.text3)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, JPSpace.m)
            .accessibilityIdentifier("spot.official.photoCredit")
        }
    }

    /// 頭の写真の高さ（板 SpotDetail 460）・下端の溶かしの高さ（板 220）
    nonisolated static let heroHeight: CGFloat = 460
    nonisolated static let heroFadeHeight: CGFloat = 220

    // MARK: - 地図（写真が無いスポットは、代表画像の位置に地図を置く）

    /// **押せない地図**（`SpotDetailView.map` と同じ形）。動かしたい人は「地図で見る」（アプリの中の地図）へ
    @ViewBuilder
    private var heroMap: some View {
        if let coords = spot.coords {
            let center = CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lng)
            Map(position: $camera) {
                Annotation(spot.name, coordinate: center) {
                    // **地図のピンは真鍮**（owner の好み・CLAUDE.md）。地図のタブと同じ印（v2 の板 SpotLanding C）
                    SpotMapMarker(photoURL: nil)
                }
            }
            .onAppear {
                camera = .region(MKCoordinateRegion(
                    center: center,
                    // **約1km に丸めた座標**なので、これ以上寄せても精度は増えない
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)))
            }
            .frame(height: 232)
            .allowsHitTesting(false)
            .accessibilityLabel(L("\(spot.name) の地図", "Map of \(spot.name)"))
        }
    }

    // MARK: - 頭

    /// 頭（眉・名前・地域と枚数）。**v2（2026-10-14・板 SpotDetail / SpotLanding）**:
    /// - 写真の上（`onPhoto`）: 眉は白 88%・名前は明朝 32 の白・地域と枚数は白 82%。影で写真から切り離す
    /// - 地図の下の黒地: 眉は真鍮（下書きは灰）・名前は明朝 32・地域と枚数は text-2
    private func header(onPhoto: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // 小見出し（モックの "PHOTO SPOT"）。**下書きなら「下書き・未確認」**
            // 眉ラベルの部品に揃える。真鍮は黒地の上だけ（写真の上は白・下書きの札は色で目立たせない）
            Text(SpotScreen.eyebrow(review: spot.isDraft))
                .jpEyebrow()
                .foregroundStyle(onPhoto ? Color.white.opacity(0.88) : (spot.isDraft ? WebTheme.muted : WebTheme.accent))
            Text(spot.name)
                .font(JPFont.photoTitle)
                .foregroundStyle(WebTheme.foreground)
            // 「[都道府県] · [市区町村] · N枚の写真」。N は数えた値
            let subtitle = SpotScreen.subtitle(region: spot.regionLabel,
                                               photoCount: photosKnown || !linked.isEmpty ? linked.count : nil)
            // 地域も枚数も無い（ストーリーから開いた地域の無いスポット）なら行を置かない
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(JPFont.mono(JPTypeScale.footnote, relativeTo: .footnote))
                    .foregroundStyle(onPhoto ? WebTheme.muted : WebTheme.text2)
            }
        }
        // 写真の上だけ字の影（`jpPhotoTextShadow` と同じ 0 2 14 / 60%）。黒地の上は影なし
        .shadow(color: Color.black.opacity(onPhoto ? 0.6 : 0), radius: 7, x: 0, y: 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, JPSpace.m)
    }

    /// 下書きの帯。文は `SpotScreen.reviewNotice` が日付ごと組み立てる
    /// （生の `draftedAt` を `Text` に渡さない）
    private func draftNotice(_ text: String) -> some View {
        // v2 の札（`JPCard`・surface-1 と白 8% の縁）に入れる
        JPCard {
            HStack(alignment: .top, spacing: JPSpace.xs) {
                Image(systemName: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(WebTheme.text3)
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(WebTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(JPSpace.s)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, JPSpace.m)
        .accessibilityIdentifier("spot.official.draftNotice")
    }

    // MARK: - 行動（行きたい・地図で見る・経路）

    /// 札の行（`SpotScreen.officialActions`）。**シェアは右上の1つだけ**（判断は `officialActions` の注記）
    private var actions: some View {
        // v2 の板 SpotDetail: 同じ幅の札を 8 のすき間で並べる（札は `SpotDetailParts.actionLabel`）
        HStack(spacing: JPSpace.xs) {
            ForEach(SpotScreen.officialActions(hasCoords: spot.coords != nil), id: \.self) { action in
                actionButton(action)
            }
        }
        .padding(.horizontal, JPSpace.m)
    }

    @ViewBuilder
    private func actionButton(_ action: SpotScreen.OfficialAction) -> some View {
        switch action {
        case .wish:
            let wanted = wishlist.contains(wishKey)
            Button {
                // ログイン中はサーバーへ送る。失敗したら戻して知らせる（`WishlistSync`）
                Task {
                    let outcome = await WishlistSync.toggle(wishKey, store: wishlist, service: environment.savedSpots)
                    if let notice = WishlistSync.notice(for: outcome) { toasts.show(notice.text, kind: notice.kind) }
                }
            } label: {
                SpotDetailParts.actionLabel(icon: wanted ? "heart.fill" : "heart",
                                            title: L("行きたい", "Want to go"), filled: wanted)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("spot.official.wish")
        case .map:
            // アプリの中の地図（マイページ・探すの「地図で見る」と同じくアプリの中・2026-10-11）
            NavigationLink {
                OfficialSpotMapView(spot: shown)
            } label: {
                SpotDetailParts.actionLabel(icon: "map", title: L("地図で見る", "View on map"), filled: false)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("spot.official.map")
        case .directions:
            // 外の地図（Apple のマップ）へ出るのはここだけ。名前で探し直してから開く（`SpotDirections`）
            Button {
                openDirections()
            } label: {
                // 探している間も名前は「経路」のまま、記号の代わりに輪を出す（2026-10-11 判断:
                // 「開いています…」は3つ並びの札に入らず、大きな文字で切れた）
                SpotDetailParts.actionLabel(icon: "arrow.triangle.turn.up.right.diamond",
                                            title: L("経路", "Directions"),
                                            filled: false, busy: openingDirections)
            }
            .buttonStyle(.plain)
            .disabled(openingDirections)
            .accessibilityValue(openingDirections ? L("開いています", "Opening") : "")
            .accessibilityLabel(L("\(spot.name)への経路", "Directions to \(spot.name)"))
            .accessibilityHint(L("Apple のマップで開きます", "Opens in Apple Maps"))
            .accessibilityIdentifier("spot.official.directions")
        }
    }

    /// 今いる場所からの経路。探している間に頁を離れたら開かない（`SpotDirections.openDirections`）
    private func openDirections() {
        guard let coords = spot.coords, !openingDirections else { return }
        openingDirections = true
        let name = spot.name
        directionsTask = Task { @MainActor in
            defer { openingDirections = false }
            await SpotDirections.openDirections(name: name, coords: coords, stillWanted: { onScreen })
        }
    }

    /// 「この場所から、次の一枚へ（見つける → 行く → 撮る → 残す）」の**説明の帯**。
    ///
    /// 2026-10-11 判断: 以前は地の札・縁・真鍮の記号・矢印でボタンに見えたのに押せなかった。
    /// 各段は頁の中に本物の操作がある（行く＝上の「経路」・撮る＝「作例を重ねて撮る」・残す＝
    /// 「ここで撮った写真を投稿する」）ので、ここは**押せる見た目をやめて1行の説明**にした
    /// （地・縁・真鍮・矢印の記号なし。真鍮は黒地の上の合図・押せるもの）。板 SpotDetail にこの帯は無い
    private var journeyCue: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("この撮影スポットから、次の一枚へ", "From this spot to your next photo"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(WebTheme.muted2)
            // 本文の最小は 12pt（CLAUDE.md）
            Text(L("見つける → 行く → 撮る → 残す", "Discover → Go → Shoot → Share"))
                .font(.caption)
                .foregroundStyle(WebTheme.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("spot.official.journeyCue")
    }

    // MARK: - 概要（書かれたものだけ）

    @ViewBuilder
    private var summary: some View {
        if let text = shown.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            Text(text)
                .font(JPFont.body)
                .lineSpacing(Self.bodyLineSpacing)
                .foregroundStyle(WebTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, JPSpace.m)
        }
    }

    /// 本文の行間（板 SpotDetail の `.body` 15 / 行の高さ 1.8 に寄せる）
    nonisolated static let bodyLineSpacing: CGFloat = 8

    // MARK: - 本文（この場所の魅力・撮影ガイド）

    @ViewBuilder
    private var bodySections: some View {
        if let body = spotBody, body.hasContent {
            if body.description != nil || !body.highlights.isEmpty {
                VStack(alignment: .leading, spacing: JPSpace.s) {
                    SpotDetailParts.sectionHeader(L("この撮影スポットの魅力", "What makes it special"),
                                                  eyebrow: "ABOUT", spoken: L("概要", "About"))
                    if let text = body.description {
                        Text(text)
                            .font(JPFont.body)
                            .lineSpacing(Self.bodyLineSpacing)
                            .foregroundStyle(WebTheme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, JPSpace.m)
                    }
                    if !body.highlights.isEmpty {
                        highlightList(body.highlights)
                    }
                }
            }
        }
        // 作例は本文の節が無くても出す（本文が作例だけの場所もある）
        samplesSection
        if let body = spotBody, body.hasContent {
            let seasons = SpotBodyText.orderedSeasons(body.seasonalGuide,
                                                      current: SpotBodyText.currentSeason(now: Date()))
            // 朝・夕の文は「光の時刻」の節を出すときだけそちらに並べ、ここは残り（日中・夜）。出さなければ全部
            let times = SpotLight.guideTimes(body.timeOfDayGuide, lightShown: lightSheet != nil)
            if !seasons.isEmpty || !times.isEmpty || !body.compositionTips.isEmpty {
                VStack(alignment: .leading, spacing: JPSpace.s) {
                    SpotDetailParts.sectionHeader(L("撮影ガイド", "Shooting guide"),
                                                  eyebrow: "GUIDE", spoken: L("撮影ガイド", "Guide"))
                    if !seasons.isEmpty {
                        seasonGroup(seasons)
                    }
                    if !times.isEmpty {
                        guideGroup(L("時間帯", "By time of day"),
                                   rows: times.map { (SpotBodyText.timeLabel($0.time) ?? "", $0.text) })
                    }
                    if !body.compositionTips.isEmpty {
                        VStack(alignment: .leading, spacing: JPSpace.xs) {
                            guideLabel(L("構図のヒント", "Composition"))
                            ForEach(Array(body.compositionTips.enumerated()), id: \.offset) { _, tip in
                                // 行頭は Web と同じ「・」（見どころは「—」）
                                bullet(tip, mark: "・")
                            }
                        }
                    }
                }
            }
        }
        // **公式サイトは本文の有無に関わらず出す**（Web と同じ）
        if let site = spotBody?.officialWebsite {
                Link(destination: site) {
                    HStack(spacing: 6) {
                        Text(L("公式サイト", "Official site"))
                            .font(JPFont.bodyEmphasis)
                            .underline()
                        // 外へ出る印（v2 の板 SpotLanding「公式サイト · … ↗」）
                        Image(systemName: "arrow.up.right")
                            .font(.footnote)
                    }
                    .frame(minHeight: WebTheme.minTapTarget)
                    // 外へ出るリンクは真鍮（黒地の上・規約や出典のリンクと同じ。2026-10-02 owner）
                    .foregroundStyle(WebTheme.accent)
                }
                .padding(.horizontal, 16)
        }
    }

    // MARK: - 作例（Wikimedia Commons・2026-10-03）

    /// 出す作例（読み込めなかった1枚は除く）。全部読めなければ節ごと隠す
    private var shownSamples: [SpotSample] {
        (spotBody?.samples ?? []).filter { !brokenSamples.contains($0.sourceUrl) }
    }

    /// 横に送る帯。1枚ごとに写真のすぐ下へ「題 / 写真: 作者 / ライセンス / Wikimedia Commons」。
    ///
    /// 2026-10-03 判断: 板（SpotDetail）の「この場所の写真」は 3列の格子だが、あれは**切り抜く**
    /// 正方形の格子。作例は切り抜かない（CC BY-SA の写真を改変と受け取られる余地を作らない・
    /// docs/spot-samples-commons.md）うえに1枚ごとに4つの項目の出典が付くので、格子では
    /// 文字が写真より長くなる。高さをそろえ、幅を写真の縦横比に合わせた横送りの帯にした。
    /// 見出し・注記・出典の文字は板の節（見出し 12・text-3）に、リンクは真鍮（黒地の上・
    /// 出典のリンクは真鍮＝CLAUDE.md の owner の好み）に合わせる
    @ViewBuilder
    private var samplesSection: some View {
        let samples = shownSamples
        if !samples.isEmpty {
            VStack(alignment: .leading, spacing: JPSpace.s) {
                SpotDetailParts.sectionHeader(SpotSampleText.heading(samples),
                                              eyebrow: "EXAMPLES", spoken: L("作例", "Examples"))
                Text(SpotSampleText.note(samples))
                    .font(.caption)
                    .foregroundStyle(WebTheme.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(samples) { sample in
                            sampleCard(sample)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                if ComposeGuide.showsEntry(sampleCount: samples.count) {
                    composeEntry
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("spot.official.samples")
            // 作例の並びと始める番号は開いた時点のもの（`ComposeGuide.Launch` の注記）。
            // 案内で Pro になったら同じ1枚から開き直す（`ComposeGuidePresenter`）
            // 撮った1枚は「投稿」でこのスポットの投稿へ進める（2026-10-14・写真から次の旅へ）。
            // 撮る画面を**閉じきってから**投稿画面を開く（`RootView` の作例なしの入口と同じ順）
            .composeGuidePresenter(composeLauncher, spotName: spot.name,
                                   onPost: { capture in pendingCapture = capture },
                                   onDismiss: { if SpotComposePost.opensUpload(pendingCapture) { showUpload = true } })
        }
    }

    // MARK: - 作例を重ねて撮る（Pro・2026-10-09）

    /// 作例の帯の下の入口。黒地の上の行（地は surface・白の字）。合図の「PRO」とカメラの記号だけ真鍮
    /// （黒地の上の合図・CLAUDE.md）。**作例が1枚も無いスポットでは出さない**（呼ぶ側）
    private var composeEntry: some View {
        // 入口のボタンは今までどおり1枚目から
        // v2 の板 SpotDetail: 角 14・白 7% の行に、真鍮の印 → 15 の太字の名前と 12 の text-3 の一言 →
        // 真鍮の縁の「PRO」の札
        Button { Task { await openComposeGuide(from: nil) } } label: {
            HStack(spacing: JPSpace.s) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(WebTheme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("作例を重ねて撮る", "Shoot with an example overlay"))
                        .font(JPFont.bodyEmphasis)
                        .foregroundStyle(WebTheme.foreground)
                    Text(L("作例の構図をカメラに重ねて、同じ所から", "Overlay the example on your camera, from the same spot"))
                        .font(.caption)
                        .foregroundStyle(WebTheme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text("PRO")
                    .font(JPFont.eyebrow)
                    .tracking(JPTypeScale.eyebrow * 0.12)
                    .foregroundStyle(WebTheme.accent)
                    .padding(.horizontal, JPSpace.xs)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: JPRadius.s)
                        .strokeBorder(WebTheme.accent.opacity(0.6), lineWidth: JPStroke.hairline))
                    .accessibilityHidden(true)
                if composeLauncher.checking {
                    ProgressView().tint(WebTheme.muted2)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WebTheme.faint)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, JPSpace.s)
            .frame(maxWidth: .infinity, minHeight: JPHeight.tallRow)
            .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: JPRadius.m))
            .contentShape(RoundedRectangle(cornerRadius: JPRadius.m))
        }
        .buttonStyle(.plain)
        .disabled(composeLauncher.checking)
        .padding(.horizontal, JPSpace.m)
        .accessibilityHint(L("Pro の機能です。カメラの映像に作例を半透明で重ねて撮ります",
                             "A Pro feature. Shoot with an example photo overlaid on the camera view."))
        .accessibilityIdentifier("spot.official.composeGuide")
    }

    /// Pro なら撮る画面、そうでなければ Pro の案内。Pro かどうかはサーバーのプロフィールで決める
    /// （`ComposeGuideLauncher`）。`sample` は始める作例の出典のページ（作例の帯で押した1枚・入口のボタンは nil＝1枚目）。
    /// 作例の並びは開く時点で読む（案内を経て開き直すときも、その時点の並び）
    private func openComposeGuide(from sample: URL?) async {
        await ComposeGuidePresenter.request(composeLauncher, make: {
            ComposeGuide.Launch(sample: sample, samples: shownSamples)
        }, auth: auth, store: store, environment: environment, toasts: toasts)
    }

    /// 作例の1枚: 写真（縦横比のまま・切り抜かない）と、その下の出典の1行。
    ///
    /// 2026-10-10 判断: **写真を押すと、その作例から「作例を重ねて撮る」を開く**（owner の報告
    /// 「作例の1枚目しか重ねられない」・TestFlight 1.0.84）。写真には押す動きが無かったので奪うものは無い。
    /// Pro でない人には入口のボタンと同じく Pro の案内（`openComposeGuide`）。出典の1行は別の当たりのまま
    private func sampleCard(_ sample: SpotSample) -> some View {
        let size = SpotSampleText.frame(aspectRatio: sample.aspectRatio)
        return VStack(alignment: .leading, spacing: 6) {
            Button { Task { await openComposeGuide(from: sample.sourceUrl) } } label: {
                RemoteImage(url: sample.src, contentMode: .fit, onSettled: { loaded in
                    // 読めなかった1枚（Commons で消えた・差し替わった）は出典ごと隠す
                    if !loaded { brokenSamples.insert(sample.sourceUrl) }
                })
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(composeLauncher.checking)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits([.isImage, .isButton])
            .accessibilityLabel(sample.accessibilityLabel)
            .accessibilityHint(L("Pro の機能です。この作例を重ねて撮ります",
                                 "A Pro feature. Shoot with this example overlaid on the camera view."))
            .accessibilityIdentifier("spot.official.sampleCard")
            sampleCreditLink(sample, width: size.width)
        }
    }

    /// 作例の出典の1行（見た目は `linkedCredit` のまま）。当たりは1行全体で高さ 44pt 以上・幅は写真と同じ
    /// （`CreditLink` の注記）。行き先が1つ（パブリックドメイン・CC0）ならそのまま開き、2つならメニューで選ぶ
    private func sampleCreditLink(_ sample: SpotSample, width: Double) -> some View {
        CreditLinksMenu(links: sample.creditLinks, accessibilityLabel: sample.credit) {
            Text(sample.linkedCredit)
                .tint(WebTheme.accent)
                .font(.caption)
                .foregroundStyle(WebTheme.text3)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .frame(width: width, alignment: .leading)
        }
        .accessibilityIdentifier("spot.official.sampleCredit")
    }

    // MARK: - 光の時刻（日の出・日の入り・ゴールデンアワー・ブルーアワー・2026-10-03）

    /// 節の中身（端末で計算する・`SpotLight.sheet`）。座標が無い・時刻帯が引けない国・段が作れない日は nil
    private var lightSheet: SpotLight.Sheet? {
        // 詳細を重ねた行で読む（時刻帯は詳細にだけ載る・分けた置き場・2026-10-07）
        guard let coords = shown.coords else { return nil }
        // 時刻帯は索引の行 → 本文 → 国の表の順（2026-10-07 判断・どれも同じ台帳の値）
        return SpotLight.sheet(country: shown.region?.country, timeZone: shown.timeZone ?? spotBody?.timeZone,
                               lat: coords.lat, lng: coords.lng,
                               offset: lightOffset, now: Date())
    }

    /// 日付は前後に送れる。黒地の札の上なので、合図（今日に戻す・眉）は真鍮、時刻は白の等幅数字
    @ViewBuilder
    private var lightSection: some View {
        if let sheet = lightSheet {
            let guides = SpotLight.guides(spotBody?.timeOfDayGuide ?? [])
            VStack(alignment: .leading, spacing: JPSpace.s) {
                SpotDetailParts.sectionHeader(L("光の時刻", "Light"),
                                              eyebrow: "LIGHT", spoken: L("光", "Light"))
                lightDateBar(SpotLight.dateLabel(sheet.ymd, offset: lightOffset, todayYMD: sheet.todayYMD))
                // v2 の札（`JPCard`・surface-1 と白 8% の縁）。朝と夕の間は札の中の線
                JPCard {
                    ForEach(Array(sheet.blocks.enumerated()), id: \.offset) { index, block in
                        if index > 0 { JPCardDivider() }
                        lightBlock(block, guides: block.isMorning ? guides.morning : guides.evening)
                    }
                }
                .padding(.horizontal, JPSpace.m)
                Text(SpotLight.note(sheet.timeZone))
                    .font(.caption)
                    .foregroundStyle(WebTheme.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("spot.official.light")
        }
    }

    /// 日付を送る帯: ‹ 10月3日（土）· 今日 ›。矢印・「今日」は当たり 44pt（label の内側で取る）。
    /// 日付は**切らない**（年付きでも折り返す）。アクセシビリティの大きさでは日付を上の行に出し、
    /// 矢印と「今日」をその下に並べる
    @ViewBuilder
    private func lightDateBar(_ label: String) -> some View {
        let date = Text(label)
            .font(JPFont.mono(15, medium: true, relativeTo: .subheadline))
            .foregroundStyle(WebTheme.foreground)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            .accessibilityIdentifier("spot.official.light.date")
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                date.padding(.horizontal, 10)
                HStack(spacing: 4) {
                    lightStepButton(-1)
                    lightStepButton(1)
                    Spacer(minLength: 8)
                    lightTodayButton
                }
            }
            .padding(.horizontal, 6)
        } else {
            HStack(spacing: 4) {
                lightStepButton(-1)
                date
                lightStepButton(1)
                Spacer(minLength: 8)
                lightTodayButton
            }
            .padding(.horizontal, 6)
        }
    }

    /// 前の日（-1）・次の日（+1）の矢印。当たりは 44pt
    private func lightStepButton(_ step: Int) -> some View {
        let atEdge = step < 0 ? lightOffset <= -SpotLight.maxOffset : lightOffset >= SpotLight.maxOffset
        return Button {
            lightOffset = min(max(lightOffset + step, -SpotLight.maxOffset), SpotLight.maxOffset)
        } label: {
            Image(systemName: step < 0 ? "chevron.left" : "chevron.right")
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(WebTheme.foreground)
        .disabled(atEdge)
        .accessibilityLabel(step < 0 ? L("前の日", "Previous day") : L("次の日", "Next day"))
        .accessibilityIdentifier(step < 0 ? "spot.official.light.prev" : "spot.official.light.next")
    }

    /// 今日でないときだけ「今日」に戻す文字ボタン（ヘッダーの文字アクションと同じ扱い＝黒地の上の手がかり＝真鍮）。
    /// 当たり 44pt は label の内側（frame＋contentShape）で取る——Button の外に付けた frame は当たりにならない
    @ViewBuilder
    private var lightTodayButton: some View {
        if lightOffset != 0 {
            Button {
                lightOffset = 0
            } label: {
                Text(L("今日", "Today"))
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(WebTheme.accent)
            .accessibilityLabel(L("今日に戻す", "Back to today"))
            .accessibilityIdentifier("spot.official.light.today")
        }
    }

    /// 朝・夕の段: 眉（真鍮）→ 時刻の行 → 台帳の時間帯の文
    private func lightBlock(_ block: SpotLight.Block, guides: [SpotBody.TimeOfDay]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(block.title)
                .jpEyebrow()
                .foregroundStyle(WebTheme.accent)
            ForEach(Array(block.rows.enumerated()), id: \.offset) { _, row in
                lightRow(row)
            }
            ForEach(Array(guides.enumerated()), id: \.offset) { _, guide in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(SpotBodyText.timeLabel(guide.time) ?? "")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(WebTheme.surface, in: Capsule())
                        .foregroundStyle(WebTheme.foreground)
                    Text(guide.text)
                        .font(JPFont.body)
                        .foregroundStyle(WebTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(JPSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 1行（札・方角・時刻）。アクセシビリティの大きさでは縦に積む（横に並べると時刻が切れる・折れる）
    @ViewBuilder
    private func lightRow(_ row: SpotLight.Row) -> some View {
        let label = Text(row.label).font(JPFont.body).foregroundStyle(WebTheme.text2)
        let detail = row.detail.map {
            Text($0).font(JPFont.mono(13, relativeTo: .footnote)).foregroundStyle(WebTheme.text3)
        }
        let value = Text(row.value)
            .font(JPFont.mono(15, medium: true, relativeTo: .subheadline))
            .foregroundStyle(WebTheme.foreground)
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                label
                value.fixedSize(horizontal: false, vertical: true)
                if let detail { detail }
            }
            .accessibilityElement(children: .combine)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                label
                Spacer(minLength: 8)
                if let detail { detail }
                value.multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// 札（季節・時間帯）と一文の行を並べる小さな段
    private func guideGroup(_ title: String, rows: [(label: String, text: String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            guideLabel(title)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(row.label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(WebTheme.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
                        .foregroundStyle(WebTheme.foreground)
                    Text(row.text)
                        .font(JPFont.body)
                        .foregroundStyle(WebTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 16)
    }

    private func guideLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(WebTheme.text3)
    }

    /// 見どころ（**v2 の板 SpotDetail**: 真鍮の等幅番号「01」・15 の本文・行の上に白 8% の線、最後の行は下にも）。
    /// v1 は「—」の行頭。黒地の上なので番号は真鍮（合図・CLAUDE.md）
    private func highlightList(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(Self.highlightNumber(index))
                        .font(JPFont.mono(JPTypeScale.footnote, relativeTo: .footnote))
                        .foregroundStyle(WebTheme.accent)
                        .frame(minWidth: 18, alignment: .leading)
                        .accessibilityHidden(true)
                    Text(line)
                        .font(JPFont.body)
                        .foregroundStyle(WebTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, JPSpace.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { JPCardDivider() }
                .overlay(alignment: .bottom) { if index == lines.count - 1 { JPCardDivider() } }
            }
        }
        .padding(.horizontal, JPSpace.m)
    }

    /// 見どころの番号（「01」「02」…）。2 桁にそろえる（板）
    nonisolated static func highlightNumber(_ index: Int) -> String {
        String(format: "%02d", index + 1)
    }

    /// 季節ごとの景色（**v2 の板 SpotDetail「THIS SEASON」**）: 今の季節は札（surface-1・角 16）に
    /// 明朝の季節名と真鍮の「NOW」の札を添え、ほかの季節はその下に線で区切って並べる。
    /// 板はほかの季節を閉じた行にしているが、ここは開いたまま（押さないと読めない文を作らない・2026-10-14 判断）
    private func seasonGroup(_ seasons: [SpotBody.Seasonal]) -> some View {
        let current = SpotBodyText.currentSeason(now: Date())
        return VStack(alignment: .leading, spacing: JPSpace.xs) {
            guideLabel(L("季節ごとの景色", "By season"))
            ForEach(Array(seasons.enumerated()), id: \.offset) { _, season in
                let label = SpotBodyText.seasonLabel(season.season) ?? ""
                if Self.isCurrentSeason(season.season, current: current) {
                    JPCard {
                        VStack(alignment: .leading, spacing: JPSpace.xs) {
                            HStack(spacing: JPSpace.xs) {
                                Text(label)
                                    .font(JPFont.rowTitle)
                                    .foregroundStyle(WebTheme.foreground)
                                // 今の季節の札（真鍮の塗りに墨・字でも「いま」と言う）
                                Text("NOW")
                                    .font(JPFont.eyebrow)
                                    .tracking(JPTypeScale.eyebrow * 0.12)
                                    .foregroundStyle(WebTheme.accentText)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(WebTheme.accent, in: RoundedRectangle(cornerRadius: 4))
                                    .accessibilityLabel(L("いまの季節", "This season"))
                            }
                            Text(season.text)
                                .font(JPFont.body)
                                .lineSpacing(Self.bodyLineSpacing)
                                .foregroundStyle(WebTheme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(JPSpace.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    VStack(alignment: .leading, spacing: JPSpace.xxs) {
                        Text(label)
                            .font(JPFont.rowTitle)
                            .foregroundStyle(WebTheme.foreground)
                        Text(season.text)
                            .font(JPFont.body)
                            .foregroundStyle(WebTheme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, JPSpace.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) { JPCardDivider() }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.horizontal, JPSpace.m)
    }

    /// 今の季節の行か（「NOW」の札を付ける）
    nonisolated static func isCurrentSeason(_ season: String, current: String) -> Bool {
        season == current
    }

    private func bullet(_ text: String, mark: String = "—") -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(mark).foregroundStyle(WebTheme.text3).accessibilityHidden(true)
            Text(text)
                .font(JPFont.body)
                .foregroundStyle(WebTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, JPSpace.m)
    }

    /// 確かめた印の1行（Web と同じ出し分け）。**本文が取れたら必ず出す**
    /// ——公式サイトのリンクや概要だけの場所でも、出典の無い事実を画面に置かない
    /// （Web も公開済みなら印の行を必ず出す）
    @ViewBuilder
    private var checkLine: some View {
        if let body = spotBody {
            // 出典の題は押せる（Web と同じ）。押すと出典のページ
            // リンクは真鍮（owner「デザインの箇所は白より真鍮色が好き」（2026-09-29））
            // v2 の板 SpotDetail の足元: 12 の text-3・出典のリンクは真鍮
            Text(SpotBodyText.linkedCheckLine(body.check))
                .tint(WebTheme.accent)
                .font(.caption)
                .foregroundStyle(WebTheme.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("spot.official.check")
        }
    }

    // MARK: - この場所の写真・近くの撮影スポット

    /// 「このスポットの写真を投稿」の形（デザインシステム「黒塗りの真鍮」と CLAUDE.md）:
    /// - 写真がもう並んでいる・この画面から投稿した → 枠線（主役は写真。二度押しを誘わない）
    /// - 写真の無い画面（代表写真も無く、上は地図）→ 真鍮の塗り（写真の無い画面の主ボタン）
    /// - 代表写真がある → 白（写真のある画面の主ボタン）
    nonisolated static func postButtonStyle(hasCover: Bool, hasLinked: Bool, postedHere: Bool) -> JPPillStyle {
        if hasLinked || postedHere { return .outline }
        // 主ボタンの色は共通の決まりで（写真のある画面は白・無い画面は真鍮）
        return .main(onPhoto: hasCover)
    }

    @ViewBuilder
    private var spotPhotos: some View {
        VStack(alignment: .leading, spacing: JPSpace.s) {
            // 写真が0枚の回は下の破線の札が見出しを持つ（同じことを二度言わない）
            if (photosKnown || !linked.isEmpty) && !showsEmptyPhotosCard {
                SpotDetailParts.sectionHeader(L("この撮影スポットの写真（\(linked.count)）", "Photos here (\(linked.count))"))
            }
            if postedHere {
                // 一覧は開いた時点の写しなので、上げた写真はすぐには並ばない。
                // 「まだありません」のままだと、上がっていないと思ってもう一度上げてしまう
                Text(L("投稿しました。この一覧に並ぶまで少し時間がかかります。",
                       "Posted. It may take a little while to appear here."))
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.text2)
                    .padding(.horizontal, JPSpace.m)
            }
            if showsEmptyPhotosCard {
                // **空を隠さない。** 紐づいた写真が無いことをそのまま言う。
                // v2 の板 SpotDetail の「写真0枚」: 破線の札に明朝 18 の見出し・13 の text-2・投稿のボタン
                VStack(spacing: JPSpace.xs) {
                    Text(L("この撮影スポットの写真（\(linked.count)）", "Photos here (\(linked.count))"))
                        .font(JPFont.rowTitle)
                        .foregroundStyle(WebTheme.foreground)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(L("まだありません。ここで撮った写真があれば、最初の1枚にしませんか。",
                           "None yet. If you've shot here, share the first one."))
                        .font(.footnote)
                        .lineSpacing(4)
                        .foregroundStyle(WebTheme.text2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    postButton
                        .padding(.top, JPSpace.xs)
                }
                .padding(.horizontal, JPSpace.l)
                .padding(.vertical, JPSpace.xl)
                .frame(maxWidth: .infinity)
                .overlay(RoundedRectangle(cornerRadius: JPRadius.l)
                    .strokeBorder(Color.white.opacity(Self.emptyDashOpacity),
                                  style: StrokeStyle(lineWidth: JPStroke.hairline, dash: [4, 4])))
                .padding(.horizontal, JPSpace.m)
            } else {
                if !linked.isEmpty {
                    PhotoGrid(photos: linked) { photo in
                        PhotoDetailView(photo: photo, context: linked)
                    }
                }
                postButton
                    .padding(.horizontal, JPSpace.m)
            }
        }
        // 閉じたら「投稿を閉じた」を出す（`RootView` の投稿と同じ）。メニューのシートから
        // 来た回はホームの `onAppear` が走らず、自分の写真（今日のテーマの参加済みなど）が古いまま残った
        .sheet(isPresented: $showUpload, onDismiss: {
            // 撮った1枚は次の投稿に持ち越さない
            pendingCapture = nil
            TabRouter.shared.postSheetClosed()
        }) {
            NavigationStack { UploadView(spot: UploadSpotTarget(spot), onPosted: { count in
                // **この一覧に並ぶ投稿があったときだけ**（外した・遠い写真・下書き・範囲を
                // 絞った投稿では並ばないので言わない）
                if count > 0 { postedHere = true }
            }, initialCapture: pendingCapture,
            // 上がった写真をマイページ・ホームに先に並べる（`RootView` の投稿と同じ・`TabRouter.lastPosted`）
            onSaved: { TabRouter.shared.notePosted($0) }) }
        }
    }

    /// 写真0枚の破線の札を出すか（読めていて、紐づいた写真が無く、この画面から投稿していない）
    private var showsEmptyPhotosCard: Bool {
        linked.isEmpty && !postedHere && photosKnown
    }

    /// 写真0枚の札の破線の白の濃さ（板 `1px dashed rgba(255,255,255,.2)`）
    nonisolated static let emptyDashOpacity = 0.2

    /// 「この撮影スポットの写真を投稿」。
    /// owner「スポットの詳細からこのスポットの写真を上げたい」（2026-09-29）。
    /// 撮影地を入れた投稿画面を開き、保存で `spotId` を付ける
    private var postButton: some View {
        Button {
            showUpload = true
        } label: {
            Label(L("この撮影スポットの写真を投稿", "Post a photo of this spot"), systemImage: "camera")
                .jpPillButton(Self.postButtonStyle(hasCover: shown.photo != nil,
                                                   hasLinked: !linked.isEmpty, postedHere: postedHere))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("spot.official.post")
    }

    @ViewBuilder
    private var nearbySpots: some View {
        let near = nearby
        if !near.isEmpty {
            VStack(alignment: .leading, spacing: JPSpace.s) {
                SpotDetailParts.sectionHeader(L("近くの撮影スポット", "Nearby spots"))
                // v2 の板 SpotDetail: 札に入れず、行の上に白 8% の線（最後の行は下にも）
                VStack(spacing: 0) {
                    ForEach(Array(near.enumerated()), id: \.element.spot.id) { index, item in
                        NavigationLink {
                            OfficialSpotView(spot: item.spot, spots: spots, photos: photos, photosKnown: photosKnown)
                        } label: {
                            nearbyRow(item.spot, km: item.km)
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .top) { JPCardDivider() }
                        .overlay(alignment: .bottom) { if index == near.count - 1 { JPCardDivider() } }
                    }
                }
                .padding(.horizontal, JPSpace.m)
            }
        }
    }

    /// 近くの1行（**v2 の板 SpotDetail**: 明朝の名前 → 13 の text-3 の等幅の距離・高さ 56）。
    /// 板の行に無い右の矢印は残す（行き先がある行の合図）。v1 の左の印（mappin）は外した
    private func nearbyRow(_ other: OfficialSpot, km: Double) -> some View {
        HStack(spacing: JPSpace.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(other.name)
                    .font(JPFont.rowTitle)
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(1)
                if other.isDraft {
                    Text(L("下書き", "Draft"))
                        .font(.caption)
                        .foregroundStyle(WebTheme.text3)
                }
            }
            Spacer(minLength: JPSpace.xs)
            // **距離は計算したもの。** 言い方は「近くの写真」と同じ関数（`NearbyPhotos.label`）
            Text(NearbyPhotos.label(km: km))
                .font(JPFont.mono(JPTypeScale.footnote, relativeTo: .footnote))
                .foregroundStyle(WebTheme.text3)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(WebTheme.text3)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Self.nearbyRowHeight)
        .contentShape(Rectangle())
    }

    /// 近くの撮影スポットの行の高さ（板 56）
    nonisolated static let nearbyRowHeight: CGFloat = 56
}

/// スポットの写真の出典の1行「写真: 作者 / ライセンス」。**1本の文字のまま**
/// （折り返し・行数・揃えは呼ぶ側の指定どおり）、部分にリンクを付ける
/// （`SpotImage.linkedCredit`: 作者 → 出典のページ・ライセンス → 文面）。
/// リンクは真鍮（owner「デザインの箇所は白より真鍮色が好き」（2026-09-29））。写真の下の黒地の行
/// 出典の1行を1つの当たり（高さ・幅 44pt 以上）にして、`links` を開く（2026-10-03・`CreditLink` の注記）。
/// 行き先が1つならそのまま開き、2つ以上ならメニューで選ぶ。0件なら押せない1行のまま。
/// `label` の見た目は変えない。文中のリンクは押させない（1行全体の当たりと取り合う）——色は文中のリンクのまま
struct CreditLinksMenu<Label: View>: View {
    let links: [CreditLink]
    /// 読み上げの名前（出典の1行の文字）
    let accessibilityLabel: String
    /// 当たりを広げたとき、字を置く位置
    var alignment: Alignment = .topLeading
    @ViewBuilder let label: () -> Label

    var body: some View {
        if links.count == 1, let only = links.first {
            Link(destination: only.url) { tapArea }
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint(only.label)
        } else if links.count > 1 {
            Menu {
                ForEach(links) { link in
                    Link(link.label, destination: link.url)
                }
            } label: {
                tapArea
            }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(L("開くページを選べます", "Choose a page to open"))
        } else {
            label()
        }
    }

    private var tapArea: some View {
        label()
            .allowsHitTesting(false)
            .frame(minWidth: CreditLink.tapHeight, minHeight: CreditLink.tapHeight, alignment: alignment)
            .contentShape(Rectangle())
    }
}

struct SpotImageCredit: View {
    let photo: SpotImage

    var body: some View {
        Text(photo.linkedCredit)
            .tint(WebTheme.accent)
    }
}

/// 撮影スポットの「作例を重ねて撮る」から投稿へ進むか（2026-10-14）。
/// 撮る画面を閉じたとき、「投稿」で撮った1枚を受け取っていれば投稿画面を開く。
/// 閉じるボタンで閉じた回（受け取っていない）は開かない
enum SpotComposePost {
    static func opensUpload(_ capture: CameraCapture?) -> Bool { capture != nil }
}
