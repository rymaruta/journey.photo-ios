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
struct OfficialSpotView: View {

    let spot: OfficialSpot
    /// 「近くの撮影スポット」を引く索引。呼び出し側が持っている一覧をそのまま渡す
    let spots: [OfficialSpot]
    /// 「この場所の写真」を引く公開写真。`spotId` で紐づいたものだけ数える
    let photos: [Photo]

    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var environment: AppEnvironment
    /// 渡された写真は開いた時点の写しなので、ブロック／通報をここで反映する。
    /// **見ている最中には絞らない**（`FavoritesView` の `photos` の注記）——
    /// 押した元の `NavigationLink` が消えると、開いている詳細がその場で閉じ、
    /// 通報の「受け付けました」も見えない。戻ってきたとき（`onAppear`）に絞る
    @EnvironmentObject private var hidden: ModerationStore
    @State private var dropped = ModerationSnapshot()

    @State private var camera: MapCameraPosition = .automatic
    /// 本文（公開済みの場所だけ取りに行く）。取れなければ nil のまま
    @State private var spotBody: SpotBody?
    /// 「このスポットの写真を投稿」から開く投稿画面
    @State private var showUpload = false
    /// この画面から投稿した（写真の一覧は開いた時点の写しなので、すぐには並ばない）
    @State private var postedHere = false

    /// **確定した紐づけだけ**（`Photo.spotId`）。撮影地の文字列では当てない
    private var linked: [Photo] { dropped.visible(photos.filter { $0.spotId == spot.spotId }) }

    private var nearby: [(spot: OfficialSpot, km: Double)] {
        OfficialSpotIndex.nearby(spot, in: spots)
    }

    /// 「行きたい」の鍵。**撮影地の鍵と混ぜない**（`SavedSpotKey`）
    private var wishKey: String { SavedSpotKey.official(spot.slug) }

    /// 端末の地図アプリへ。**座標があるときだけ**（`SpotScreen`）
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
            VStack(alignment: .leading, spacing: 18) {
                // 写真があれば写真を主役に（モック13の代表画像の位置）。無ければ地図
                if let photo = spot.photo {
                    heroPhoto(photo)
                } else {
                    heroMap
                }
                header
                if let notice = SpotScreen.reviewNotice(review: spot.isDraft, draftedAt: spot.draftedAt) {
                    draftNotice(notice)
                }
                actions
                journeyCue
                summary
                // **写真が主役。** 写真がある場所は本文より先に出す
                if !linked.isEmpty { spotPhotos }
                bodySections
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
        .onAppear { dropped = hidden.snapshot }
        // 下書き→公開に差し替わったら取り直す（slug だけだと走り直さない）
        .task(id: "\(spot.slug)|\(spot.isDraft)") {
            // 下書きは取りに行かない（本文は公開済みの場所にしか無い）
            guard !spot.isDraft else {
                spotBody = nil
                return
            }
            let fetched = await environment.spots.fetchBody(slug: spot.slug)
            guard !Task.isCancelled else { return }
            spotBody = fetched
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
            }
        }
        .accessibilityIdentifier("spot.official")
    }

    // MARK: - 代表写真（Wikimedia Commons・2026-09-26）

    /// 横いっぱい・4:3 の写真と、その下に出典の1行。
    /// **出典は写真と必ず一緒に**（CC BY・CC BY-SA の条件）。押すと Commons のページへ
    private func heroPhoto(_ photo: SpotImage) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            Color.clear
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay(RemoteImage(url: photo.url))
                .clipped()
                // `Color.clear` は読み上げの対象にならないので、1つの画像としてまとめて名前を付ける
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isImage)
                .accessibilityLabel(L("\(spot.name) の写真", "Photo of \(spot.name)"))
            SpotImageCredit(photo: photo)
                .font(.caption)
                .foregroundStyle(WebTheme.muted2)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("spot.official.photoCredit")
        }
    }

    // MARK: - 地図（写真が無いスポットは、代表画像の位置に地図を置く）

    /// **押せない地図**（`SpotDetailView.map` と同じ形）。動かしたい人は「地図で見る」へ
    @ViewBuilder
    private var heroMap: some View {
        if let coords = spot.coords {
            let center = CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lng)
            Map(position: $camera) {
                Annotation(spot.name, coordinate: center) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(WebTheme.foreground)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 小見出し（モックの "PHOTO SPOT"）。**下書きなら「下書き・未確認」**
            // 眉ラベルの部品に揃える。黒地なので真鍮（下書きの札は色で目立たせない）
            Text(SpotScreen.eyebrow(review: spot.isDraft))
                .jpEyebrow()
                .foregroundStyle(spot.isDraft ? WebTheme.muted : WebTheme.accent)
            Text(spot.name)
                .font(JPFont.display(28, relativeTo: .title))
                .foregroundStyle(WebTheme.foreground)
            // 「[都道府県] · [市区町村] · N枚の写真」。N は数えた値
            Text(SpotScreen.subtitle(region: spot.regionLabel, photoCount: linked.count))
                .font(.system(size: 12))
                .foregroundStyle(WebTheme.muted2)
        }
        .padding(.horizontal, 16)
    }

    /// 下書きの帯。文は `SpotScreen.reviewNotice` が日付ごと組み立てる
    /// （生の `draftedAt` を `Text` に渡さない）
    private func draftNotice(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(WebTheme.muted2)
            Text(text)
                .font(.footnote)
                .foregroundStyle(WebTheme.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .accessibilityIdentifier("spot.official.draftNotice")
    }

    // MARK: - 行動（行きたい・地図で見る・シェア）

    private var actions: some View {
        HStack(spacing: 10) {
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

            if let url = mapURL {
                Link(destination: url) {
                    SpotDetailParts.actionLabel(icon: "map", title: L("地図で見る", "Open in Maps"), filled: false)
                }
                .buttonStyle(.plain)
            }

            ShareLink(item: shareText) {
                SpotDetailParts.actionLabel(icon: "square.and.arrow.up", title: L("シェア", "Share"), filled: false)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    /// スポット詳細を「読むだけ」で終わらせず、Journey Photoの循環を一目で伝える。
    /// 実データの件数は捏造せず、行動だけを示す。
    private var journeyCue: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("この場所から、次の一枚へ", "From this place to your next photo"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WebTheme.foreground)
            HStack(spacing: 0) {
                journeyStep("map", L("見つける", "Discover"))
                journeyArrow
                journeyStep("figure.walk", L("行く", "Go"))
                journeyArrow
                journeyStep("camera", L("撮る", "Shoot"))
                journeyArrow
                journeyStep("square.and.arrow.up", L("残す", "Share"))
            }
        }
        .padding(14)
        .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WebTheme.border, lineWidth: 1))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("spot.official.journeyCue")
    }

    private func journeyStep(_ icon: String, _ title: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 15, weight: .medium)).foregroundStyle(WebTheme.accent)
            // 本文の最小は 12pt（CLAUDE.md）
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(WebTheme.muted2)
                .multilineTextAlignment(.center).lineLimit(2)
        }.frame(maxWidth: .infinity)
    }

    private var journeyArrow: some View {
        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(WebTheme.faint).accessibilityHidden(true)
    }

    // MARK: - 概要（書かれたものだけ）

    @ViewBuilder
    private var summary: some View {
        if let text = spot.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(WebTheme.muted)
                .padding(.horizontal, 16)
        }
    }

    // MARK: - 本文（この場所の魅力・撮影ガイド）

    @ViewBuilder
    private var bodySections: some View {
        if let body = spotBody, body.hasContent {
            if body.description != nil || !body.highlights.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SpotDetailParts.sectionHeader(L("この場所の魅力", "What makes it special"))
                    if let text = body.description {
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(WebTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 16)
                    }
                    ForEach(Array(body.highlights.enumerated()), id: \.offset) { _, line in
                        bullet(line)
                    }
                }
            }
            let seasons = SpotBodyText.orderedSeasons(body.seasonalGuide,
                                                      current: SpotBodyText.currentSeason(now: Date()))
            let times = SpotBodyText.orderedTimes(body.timeOfDayGuide)
            if !seasons.isEmpty || !times.isEmpty || !body.compositionTips.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SpotDetailParts.sectionHeader(L("撮影ガイド", "Shooting guide"))
                    if !seasons.isEmpty {
                        guideGroup(L("季節ごとの景色", "By season"),
                                   rows: seasons.map { (SpotBodyText.seasonLabel($0.season) ?? "", $0.text) })
                    }
                    if !times.isEmpty {
                        guideGroup(L("時間帯", "By time of day"),
                                   rows: times.map { (SpotBodyText.timeLabel($0.time) ?? "", $0.text) })
                    }
                    if !body.compositionTips.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
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
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "arrow.up.right.square")
                            .font(.footnote)
                    }
                    .frame(minHeight: 44)
                    .foregroundStyle(WebTheme.foreground)
                }
                .padding(.horizontal, 16)
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
                        .foregroundStyle(WebTheme.foreground)
                    Text(row.text)
                        .font(.subheadline)
                        .foregroundStyle(WebTheme.muted)
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
            .foregroundStyle(WebTheme.muted2)
    }

    private func bullet(_ text: String, mark: String = "—") -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(mark).foregroundStyle(WebTheme.muted2).accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(WebTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
    }

    /// 確かめた印の1行（Web と同じ出し分け）。**本文が取れたら必ず出す**
    /// ——公式サイトのリンクや概要だけの場所でも、出典の無い事実を画面に置かない
    /// （Web も公開済みなら印の行を必ず出す）
    @ViewBuilder
    private var checkLine: some View {
        if let body = spotBody {
            // 出典の題は押せる（Web と同じ）。押すと出典のページ
            // リンクは真鍮（owner「デザインの箇所は白より真鍮色が好き」（2026-09-29））
            Text(SpotBodyText.linkedCheckLine(body.check))
                .tint(WebTheme.accent)
                .font(.caption)
                .foregroundStyle(WebTheme.muted2)
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
        return hasCover ? .primary : .accent
    }

    @ViewBuilder
    private var spotPhotos: some View {
        VStack(alignment: .leading, spacing: 10) {
            SpotDetailParts.sectionHeader(L("この場所の写真（\(linked.count)）", "Photos here (\(linked.count))"))
            if postedHere {
                // 一覧は開いた時点の写しなので、上げた写真はすぐには並ばない。
                // 「まだありません」のままだと、上がっていないと思ってもう一度上げてしまう
                Text(L("投稿しました。この一覧に並ぶまで少し時間がかかります。",
                       "Posted. It may take a little while to appear here."))
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.muted)
                    .padding(.horizontal, 16)
            }
            if linked.isEmpty && !postedHere {
                // **空を隠さない。** 紐づいた写真が無いことをそのまま言う
                Text(L("まだありません。ここで撮った写真があれば、最初の1枚にしませんか。",
                       "None yet. If you've shot here, share the first one."))
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.muted2)
                    .padding(.horizontal, 16)
            } else if !linked.isEmpty {
                PhotoGrid(photos: linked) { photo in
                    PhotoDetailView(photo: photo, context: linked)
                }
            }
            // owner「スポットの詳細からこのスポットの写真を上げたい」（2026-09-29）。
            // 撮影地を入れた投稿画面を開き、保存で `spotId` を付ける
            Button {
                showUpload = true
            } label: {
                Label(L("このスポットの写真を投稿", "Post a photo of this spot"), systemImage: "camera")
                    .jpPillButton(Self.postButtonStyle(hasCover: spot.photo != nil,
                                                       hasLinked: !linked.isEmpty, postedHere: postedHere))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .accessibilityIdentifier("spot.official.post")
        }
        .sheet(isPresented: $showUpload) {
            NavigationStack { UploadView(spot: UploadSpotTarget(spot), onPosted: { count in
                // **この一覧に並ぶ投稿があったときだけ**（外した・遠い写真・下書き・範囲を
                // 絞った投稿では並ばないので言わない）
                if count > 0 { postedHere = true }
            }) }
        }
    }

    @ViewBuilder
    private var nearbySpots: some View {
        let near = nearby
        if !near.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SpotDetailParts.sectionHeader(L("近くの撮影スポット", "Nearby spots"))
                VStack(spacing: 0) {
                    ForEach(near, id: \.spot.id) { item in
                        NavigationLink {
                            OfficialSpotView(spot: item.spot, spots: spots, photos: photos)
                        } label: {
                            nearbyRow(item.spot, km: item.km)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
            }
        }
    }

    /// 近くの1行（モック13）: 印 → 名前 → 距離 → 矢印。表紙は無い（写真が無い）
    private func nearbyRow(_ other: OfficialSpot, km: Double) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle")
                .foregroundStyle(WebTheme.muted2)
            VStack(alignment: .leading, spacing: 3) {
                Text(other.name)
                    .font(.system(size: 15))
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(1)
                if other.isDraft {
                    Text(L("下書き", "Draft"))
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                }
            }
            Spacer(minLength: 8)
            // **距離は計算したもの。** 言い方は「近くの写真」と同じ関数（`NearbyPhotos.label`）
            Text(NearbyPhotos.label(km: km))
                .font(.system(size: 13))
                .foregroundStyle(WebTheme.faint)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(WebTheme.placeholder)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }
}

/// スポットの写真の出典の1行「写真: 作者 / ライセンス」。**1本の文字のまま**
/// （折り返し・行数・揃えは呼ぶ側の指定どおり）、部分にリンクを付ける
/// （`SpotImage.linkedCredit`: 作者 → 出典のページ・ライセンス → 文面）。
/// リンクは真鍮（owner「デザインの箇所は白より真鍮色が好き」（2026-09-29））。写真の下の黒地の行
struct SpotImageCredit: View {
    let photo: SpotImage

    var body: some View {
        Text(photo.linkedCredit)
            .tint(WebTheme.accent)
    }
}
