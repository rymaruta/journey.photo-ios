import SwiftUI

/// 旅の一冊（板 03）。
///
/// **表紙 → 数字 → ルート図 → 日ごとのページ**の順に、下へ流れる1本の読み物にする。
/// 写真を「並べる」のではなく「読ませる」——ここが一覧との違い。
struct TripBookView: View {

    /// 開いたときの旅。**描くのは `book`**（消した写真を落としたもの）
    let trip: TripBook.Trip
    /// 写真に個別ページが在るか（`PhotoDetailView.fromPublicFeed`）。
    /// **公開一覧に載っている写真だけ真**（`LikedPhotos.fromPublicFeed`）——旅は自分の
    /// 写真から作るので、投稿直後の写真はページがまだ無い。一覧を持たない入口は既定の偽
    /// （必ず開ける `/?photo=` に落ちる）
    var isPublic: (Photo) -> Bool = { _ in false }

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var hidden: ModerationStore
    /// 一冊から落とす「見せない」の写し。**戻ってきたとき（`onAppear`）に取る**
    /// （`CollectionPhotosScreen` と同じ）。旅は開いた時点の値なので、ここから開いた
    /// 詳細で消した写真が、戻っても表紙・数字・ページに残っていた
    @State private var dropped = ModerationSnapshot()
    /// 戻るスワイプ途中の `onAppear` でページを消さない印（`FrontConfirm`）
    @State private var front = FrontConfirm()
    @State private var frontSettle: Task<Void, Never>?

    /// 消した・非公開にした写真を落とした一冊
    private var book: TripBook.Trip { Self.visible(trip, dropped: dropped) }
    /// 共有する1枚の画像（`TripBookCard`）。**作れるまでは文だけを配る**（表紙が読めない・圏外でも共有できる）
    @State private var cardURL: URL?
    /// その画像を作った人。**人が替わったときだけ**共有を文に戻す（表紙が替わっただけなら前の画像のまま・
    /// 同じファイルを上書きするので、作り直しの間に共有のボタンが文に切り替わらない）
    @State private var cardOwner: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                cover
                stats
                    .padding(.horizontal, JPSpace.l)
                    .padding(.top, JPSpace.m)
                route
                    .padding(.horizontal, JPSpace.gutter)
                    .padding(.top, JPSpace.xl)
                pages
            }
            .padding(.bottom, JPSpace.emptyTop)
        }
        .webScreen()
        // **共有は下端の白い全幅「この一冊を送る」に一本化**（v2 の板 TripBookShare の C-1・2026-10-14）。
        // 右上の印は探しにくく、何を配るのか分からなかった。写真のある画面なので主ボタンは白
        // （`JPPillStyle.main(onPhoto: true)`）。自分だけの一冊は出さない（`TripBook.canShare`）
        .safeAreaInset(edge: .bottom) {
            if TripBook.canShare(book) {
                shareButton.jpBottomBar()
            }
        }
        .onAppear {
            switch front.appear() {
            case .first:
                dropped = hidden.snapshot
            case .returning:
                frontSettle?.cancel()
                frontSettle = Task {
                    try? await Task.sleep(nanoseconds: FrontConfirm.settleNanoseconds)
                    guard !Task.isCancelled, front.confirm() else { return }
                    dropped = hidden.snapshot
                }
            }
        }
        .onDisappear {
            frontSettle?.cancel()
            frontSettle = nil
            front.disappear()
        }
        .navigationTitle(TripBook.title(of: book))
        .navigationBarTitleDisplayMode(.inline)
        // 開いたときに1回だけ作っておく（押してから待たせない）。同じ旅なら同じファイルを上書き。
        // **表紙・枚数が変わったら作り直す**（表紙はいいねの数で選ぶので、写真が同じでも替わる）
        // **人が替わったら作り直す**（サインアウトしても この画面は残る。前の人の画像を指したままにしない）
        .task(id: "\(book.id)|\(book.cover?.id ?? "")|\(book.photos.count)|\(auth.userId ?? "")") {
            if cardOwner != auth.userId { cardURL = nil }
            cardOwner = auth.userId
            // **作れなかったら前の画像を捨てる**（表紙・枚数が替わったのに前の1枚を配っていた・
            // eaf0c48 のレビュー）。取り消されただけ（すぐ次の作り直しが来る）なら触らない
            let made = await makeCard()
            if !Task.isCancelled { cardURL = made }
        }

    }

    /// 下端の「この一冊を送る」。**配るのは表紙と題・期間・数字を載せた1枚**（2026-09-30）。
    /// 作れるまでは題と期間の文（URL を持たない理由は `TripBook.shareText`）
    @ViewBuilder
    private var shareButton: some View {
        if let cardURL {
            // 共有シートに題を出す（ファイル名を出さない）
            ShareLink(item: cardURL, preview: SharePreview(TripBook.title(of: book))) { shareLabel }
                .buttonStyle(.plain)
                .accessibilityIdentifier("trips.share")
        } else {
            ShareLink(item: TripBook.shareText(of: book)) { shareLabel }
                .buttonStyle(.plain)
                .accessibilityIdentifier("trips.share")
        }
    }

    private var shareLabel: some View {
        Label(Self.shareTitle, systemImage: "square.and.arrow.up")
            .jpPillButton(.main(onPhoto: true))
    }

    nonisolated static var shareTitle: String { L("この一冊を送る", "Send this trip book") }

    /// 共有する1枚を作って、端末の一時置き場に書く。**作れなければ nil**（文で共有する）。
    /// 描くのは**画面の処理の外で**（写真の展開と JPEG の書き出しで画面を引っかけない）
    private func makeCard() async -> URL? {
        let owner = auth.userId
        guard owner != nil else { return nil }
        var cover: Data?
        if let url = book.cover?.detailImageURL {
            cover = await TripBookCardRenderer.coverData(url)
        }
        guard !Task.isCancelled else { return nil }
        let lines = TripBookCard.lines(of: book, distance: distance)
        let focal = book.cover?.focalPoint
        let data = await Task.detached(priority: .utility) {
            TripBookCardRenderer.render(lines, cover: cover, focal: focal)
        }.value
        // 🔴 **作っている間に人が替わっていたら書かない**。サインアウトの片付け（`TripBookCard.removeAll`）の
        // 後に書くと、前の人の表紙の写真が次の人の端末に残った（6ff1954 のレビュー）
        guard !Task.isCancelled, !data.isEmpty, auth.userId == owner, owner != nil else { return nil }
        return TripBookCard.write(data, for: book)
    }

    // MARK: - 表紙

    /// 小見出し → 題 → 期間の範囲（板 03・v2 の板 TripBook: 表紙は 390 幅で 520 の 3:4・題は Display）
    private var cover: some View {
        ZStack(alignment: .bottomLeading) {
            if let cover = book.cover {
                Color.clear
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay {
                        RemoteImage(url: cover.detailImageURL, alignment: cover.gridAlignment)
                    }
                    .clipped()
            }
            // **下だけ暗くする。** 全面に膜を掛けると写真が濁る。下端は地の黒に
            // つなげて、表紙から数字の枠へ切れ目なく流す（板 03）
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black],
                startPoint: .center, endPoint: .bottom
            )
            .accessibilityHidden(true)
            // 上も少し暗く（板: 黒 50% → 140pt で 0）。上のバーの戻るを、明るい空の写真の上で読ませる
            VStack(spacing: 0) {
                LinearGradient(colors: [Color.black.opacity(TripStyle.bookTopShade), Color.black.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: TripStyle.bookTopShadeHeight)
                Spacer(minLength: 0)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                // 眉ラベル。**写真の上なので白**（板は真鍮だが、真鍮は夕日の
                // 写真の上で読めなくなる・`BrandPalette` の規則）
                Text(L("TRIP BOOK · 自動でまとまった旅", "TRIP BOOK · Put together for you"))
                    .jpEyebrow()
                    .foregroundStyle(Color.white.opacity(0.88))
                    // 読み上げは「旅の一冊」（「トリップブック」と英語で読ませない）
                    .accessibilityLabel(L("旅の一冊 · 自動でまとまった旅", "Trip book · Put together for you"))
                // v2: 字の段の Display（32・`JPTypeScale.display` が「旅の一冊の表紙」）。板の絵は 36
                Text(TripBook.title(of: book))
                    .font(JPFont.photoTitle)
                    .foregroundStyle(WebTheme.foreground)
                    .shadow(color: Color.black.opacity(0.5), radius: 7, y: 2)
                Text("\(TripBook.dateRange(from: book.start, to: book.end)) · \(TripBook.daysLabel(book.days))")
                    .font(JPFont.mono(13, relativeTo: .footnote))
                    .foregroundStyle(WebTheme.muted)
                // 撮影日の無い写真だけの旅（投稿した日でまとめた）。写真の上なので白の札
                if TripStyle.groupedByUploadDate(book.photos) {
                    UploadDateChip(onPhoto: true)
                }
            }
            .padding(.horizontal, JPSpace.l)
            .padding(.bottom, 18)
        }
    }

    // MARK: - 数字

    /// 枚・撮影地・移動（直線）の3つの数（板 03）。距離は**写真の座標を直線で
    /// つないだ合計**で、道のりではない（`TravelDistance`）。だから札は「直線」。
    ///
    /// **v2（2026-10-14・板 TripBook）**: 升の枠をやめ、大きな数字（`JPFont.figureLarge`・数の段と同じ semibold）と
    /// 12 の灰の札を3列に並べる
    private var stats: some View {
        HStack(alignment: .top, spacing: JPSpace.xs) {
            statCell("\(book.photos.count)", unit: nil, label: L("枚", "Photos"))
            statCell("\(TripBook.placeCount(of: book.photos))", unit: nil, label: L("撮影地", "Places"))
            statCell(TripBook.distanceText(distance), unit: distance == nil ? nil : "km",
                     label: L("移動（直線）", "Distance (straight)"))
        }
        // 3つを1つの要素に（読み上げは「12 枚、3 撮影地、…」と続けて読む）。
        // スクリーンショットの `31-旅の足取り` がルート図の無い旅で代わりに探す
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trips.stats")
    }

    /// 数1つ（板 TripBook の `.fig`: 28 の細い数字 → 12 の text-3）
    private func statCell(_ value: String, unit: String?, label: String) -> some View {
        VStack(alignment: .leading, spacing: JPSpace.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(JPFont.figureLarge)
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit)
                        .font(JPFont.mono(13, relativeTo: .footnote))
                        .foregroundStyle(WebTheme.text3)
                }
            }
            Text(label)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - ルート図

    /// 点線でつないだ足取り（板 03 の「たどった場所」）。
    /// **2か所以上のときだけ**出す（`TripBook.routeStops`）
    @ViewBuilder
    private var route: some View {
        let stops = TripBook.sampledStops(TripBook.routeStops(of: book))
        if !stops.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                // v2: 真鍮の眉と右へ消える線（板 TripBook）
                JPEyebrowLine(L("たどった場所", "Where you went"))
                // 「ROUTE」の行は図の上に別の行として置く（図の中に重ねると、
                // 大きな字で上の札とぶつかる）
                VStack(alignment: .leading, spacing: 0) {
                    Text("ROUTE · \(TripBook.distanceText(distance))\(distance == nil ? "" : " km")")
                        .font(JPFont.meta)
                        .tracking(1.5)
                        .foregroundStyle(WebTheme.text3)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                    GeometryReader { proxy in
                        routeDrawing(stops, width: proxy.size.width)
                    }
                    .frame(height: TripRouteLayout.height(labelHeight: routeLabelHeight))
                }
                .jpCardFace(fill: Self.cellColor)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.routeSpokenLabel(stops))
                // スクリーンショットの `31-旅の足取り` がここまで送って撮る
                .accessibilityIdentifier("trips.route")
            }
        }
    }

    /// 札1行の高さ。字の大きさの設定に合わせて伸びる（札の字と同じ `.caption` に追従）
    @ScaledMetric(relativeTo: .caption) private var routeLabelLine: CGFloat = 16
    /// 札は2行（DAY n／地名）
    private var routeLabelHeight: CGFloat { routeLabelLine * 2 }

    /// 置き方は `TripRouteLayout`（はみ出さない・同じ側で重ねない・高さは札から決める）
    private func routeDrawing(_ stops: [TripBook.RouteStop], width: CGFloat) -> some View {
        let layout = TripRouteLayout.layout(count: stops.count, width: width, labelHeight: routeLabelHeight)
        let points = layout.points
        let line = Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for index in points.indices.dropFirst() {
                let from = points[index - 1], to = points[index]
                let half = (to.x - from.x) / 2
                path.addCurve(to: to,
                              control1: CGPoint(x: from.x + half, y: from.y),
                              control2: CGPoint(x: to.x - half, y: to.y))
            }
        }
        return ZStack(alignment: .topLeading) {
            // v2: 真鍮の細い実線（板 TripBook。v1 の淡い帯と点線をやめた）
            line.stroke(WebTheme.accent, style: StrokeStyle(lineWidth: TripStyle.routeLineWidth,
                                                            lineCap: .round, lineJoin: .round))
            ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                let point = points[index]
                let label = layout.labels[index]
                let isLast = index == stops.count - 1
                // 番号の丸（板 TripBook: 黒に真鍮の線と数字。終点だけ真鍮の塗りに墨の数字＝どこで旅が終わったか）
                Text("\(index + 1)")
                    .font(JPFont.number(JPTypeScale.caption, weight: .bold))
                    .foregroundStyle(isLast ? WebTheme.accentText : WebTheme.accent)
                    .frame(width: TripStyle.routeDot, height: TripStyle.routeDot)
                    .background(isLast ? WebTheme.accent : Color.black, in: Circle())
                    .overlay(Circle().strokeBorder(WebTheme.accent, lineWidth: TripStyle.stopNumberStroke))
                    .position(x: point.x, y: point.y)
                // 低い点は下に、高い点は上に札を出す（線と重ねない）。
                // 2行にして地名に札の幅を丸ごと使う（1行に「DAY n · 」と並べると地名がほぼ切れた）
                VStack(spacing: 0) {
                    Text("DAY \(stop.day)")
                        .font(JPFont.meta)
                    // 画面に出す形（`LocationMatch.display`）。同じ日かどうかの比べは元の文字のまま
                    Text(LocationMatch.display(stop.place))
                        .font(JPFont.caption)
                }
                .foregroundStyle(WebTheme.text3)
                .lineLimit(1)
                .frame(width: label.width, height: routeLabelHeight)
                .position(x: label.centerX, y: label.centerY)
            }
        }
    }

    // MARK: - ページ

    /// **日ごとの段に、写真を1枚ずつ大きく。** 一覧の格子と同じ見せ方にすると、
    /// 「一冊」にならない（板 03 は小さく3枚並べるが、ここは意図して変えない）。
    /// 段の頭は板と同じ DAY n／MM.dd
    ///
    /// **`LazyVStack` に平らに並べる（2026-10-02）。** 入れ子の `VStack` だと開いた瞬間に全ページの
    /// 元画像（`detailImageURL`）を読んでいた。間は行ごとの上の余白で前と同じ（`TripBook.pageRows`）
    private var pages: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(TripBook.pageRows(of: TripBook.days(of: book))) { row in
                Group {
                    switch row.kind {
                    case .header(let day):
                        dayHeader(day)
                    case .page(let photo, let dayPlace):
                        page(photo, dayPlace: dayPlace)
                    }
                }
                .padding(.top, row.topSpacing)
            }
        }
        .padding(.horizontal, JPSpace.gutter)
        .padding(.top, JPSpace.section)
    }

    /// 日の見出し（v2 の板 TripBook: 真鍮の眉「DAY 1 · 09.12」と右へ消える線 → 明朝 22 の地名）。
    /// 形は共通の節の見出し（`JPSectionHeading`・2026-10-14 判断）。地名が無い日は眉だけ
    private func dayHeader(_ day: TripBook.Day) -> some View {
        JPSectionHeading(eyebrow: "DAY \(day.number) · \(TripBook.monthDay(day.date))",
                         spoken: Self.spokenDayHeader(day.number, monthDay: TripBook.monthDay(day.date)),
                         title: day.place.isEmpty ? nil : LocationMatch.display(day.place))
            .padding(.bottom, JPSpace.s)
    }

    /// ページの写真。**寸法が分かれば、読み込む前に縦横比で枠を取る**（2026-10-02）——
    /// ページは `LazyVStack` で遅れて読むので、枠が無いと絵が出た瞬間に下のページが跳ねる
    ///
    /// **表示する幅に縮めて読む**（`DownsampledRemoteImage`・2026-10-03）。元の画像（1920px）を
    /// そのまま展開すると、通り過ぎたページの絵を抱えたまま長い旅でメモリが膨らみうる
    @ViewBuilder
    private func pageImage(_ photo: Photo) -> some View {
        if let ratio = photo.aspectRatio {
            DownsampledRemoteImage(url: photo.detailImageURL, contentMode: .fit, aspectRatio: CGFloat(ratio))
                .aspectRatio(ratio, contentMode: .fit)
        } else {
            DownsampledRemoteImage(url: photo.detailImageURL, contentMode: .fit)
        }
    }

    private func page(_ photo: Photo, dayPlace: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                // 旅の一冊は自分の写真だけ（`TripBook.shelfTrips(from: myPhotos)`）。
                // 投稿直後の写真は個別ページがまだ無い（`PhotoLink`）ので、公開一覧に
                // 載っているかで決める（`isPublic`）
                PhotoDetailView(photo: photo, fromPublicFeed: isPublic(photo), context: book.photos)
            } label: {
                pageImage(photo)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: JPRadius.m))
                    // 絵だけのリンク。写真の題（無ければ撮影地）を読み上げる
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isImage)
                    .accessibilityLabel(photo.accessibilityText)
            }
            .buttonStyle(.plain)
            // 写真は文字の端より左右 8 ずつ広げる（板 TripBook の margin 0 -8・写真が主役）
            .padding(.horizontal, -JPSpace.xs)

            if !photo.displayTitle.isEmpty {
                Text(photo.displayTitle)
                    .font(JPFont.rowTitle)
                    .foregroundStyle(WebTheme.foreground)
            }
            if let first = photo.paragraphs.first {
                Text(first)
                    .font(JPFont.body)
                    .lineSpacing(5)
                    .foregroundStyle(WebTheme.text2)
            }
            // 撮影時刻と設定（板「07:12 · 24mm · f/8」・等幅）
            if let meta = TripStyle.pageMeta(photo) {
                Text(meta)
                    .font(JPFont.meta)
                    .foregroundStyle(WebTheme.text3)
            }
            // 撮影地は**段の頭と違うときだけ**（同じ地名を毎枚くり返さない）
            if let place = photo.location?.trimmingCharacters(in: .whitespacesAndNewlines),
               !place.isEmpty, place != dayPlace {
                Text(LocationMatch.display(place))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
            }
            // その日に聴いていた曲（付けてあれば）
            if let song = photo.song {
                SongRow(song: song)
            }
        }
    }

    // MARK: - 計算

    /// 一冊から消した・非公開にした写真を落とす（`ModerationSnapshot.visible`・他の一覧と同じ）。
    /// 題・期間は開いたときのまま（`id` も変えない——共有の画像を同じファイルに書く）。
    ///
    /// **束の一冊（`groupId`）は、非公開にした写真を落とさない**（2026-10-07 判断）。束は公開・非公開に
    /// 関係なく一冊（`TripBook.groupTrips`）で、棚もそう数える。落とすと一冊の中だけ消えて、
    /// 棚の枚数とずれた。落とすのはブロック・通報と、**消した**写真（`ModerationSnapshot.deleted`）だけ
    nonisolated static func visible(_ trip: TripBook.Trip, dropped: ModerationSnapshot) -> TripBook.Trip {
        let photos: [Photo]
        if trip.groupId != nil {
            photos = BlockFilter.photos(trip.photos, blocked: dropped.blocked, reported: dropped.reported)
                .filter { !dropped.deleted.contains($0.id) }
        } else {
            photos = dropped.visible(trip.photos)
        }
        // 束の印・「自分だけ」の印も引き継ぐ（落とすと、開いた一冊で鍵と札の鍵が食い違う）
        return TripBook.Trip(id: trip.id, place: trip.place, start: trip.start, end: trip.end,
                             photos: photos, timeZone: trip.timeZone,
                             groupId: trip.groupId, isPrivate: trip.isPrivate)
    }

    /// 移動（直線）。数えられなければ nil（枠には「—」）
    private var distance: Double? { TravelDistance.countableTotal(of: book.photos, timeZone: book.timeZone) }

    /// ルート図の地（v2 の板 TripBook の `#0B0C0E`）
    private static let cellColor = Color(red: Double((TripStyle.routeGround >> 16) & 0xFF) / 255,
                                         green: Double((TripStyle.routeGround >> 8) & 0xFF) / 255,
                                         blue: Double(TripStyle.routeGround & 0xFF) / 255)

    /// 読み上げの「何日目」。**見た目の「DAY n」をそのまま読ませない**
    /// ——日本語の読み上げでは「ディーエーワイ」「デイ」になり、何の数か伝わらない
    nonisolated static func spokenDay(_ number: Int) -> String {
        L("\(number)日目", "Day \(number)")
    }

    /// 日の見出しの読み上げ（「1日目 · 09.12」）。眉の英字「DAY」を読ませない
    nonisolated static func spokenDayHeader(_ number: Int, monthDay: String) -> String {
        "\(spokenDay(number)) · \(monthDay)"
    }

    /// ルート図の読み上げ（「1日目 金沢、2日目 富山」）
    nonisolated static func routeSpokenLabel(_ stops: [TripBook.RouteStop]) -> String {
        stops.map { "\(spokenDay($0.day)) \($0.place)" }.joined(separator: L("、", ", "))
    }
}
