import SwiftUI

/// 旅の一冊（板 03）。
///
/// **表紙 → 数字 → ルート図 → 日ごとのページ**の順に、下へ流れる1本の読み物にする。
/// 写真を「並べる」のではなく「読ませる」——ここが一覧との違い。
struct TripBookView: View {

    let trip: TripBook.Trip
    /// 写真に個別ページが在るか（`PhotoDetailView.fromPublicFeed`）。
    /// **公開一覧に載っている写真だけ真**（`LikedPhotos.fromPublicFeed`）——旅は自分の
    /// 写真から作るので、投稿直後の写真はページがまだ無い。一覧を持たない入口は既定の偽
    /// （必ず開ける `/?photo=` に落ちる）
    var isPublic: (Photo) -> Bool = { _ in false }

    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                cover
                VStack(alignment: .leading, spacing: 16) {
                    stats
                    route
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                pages
            }
            .padding(.bottom, 32)
        }
        .webScreen()
        .navigationTitle(TripBook.title(of: trip))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 板の右上の「共有」。**配るのは題と期間の文だけ**（URL を持たない理由は
            // `TripBook.shareText`）
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: TripBook.shareText(of: trip)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .webToolbarIcon()
                .accessibilityLabel(L("共有", "Share"))
            }
        }
    }

    // MARK: - 表紙

    /// 小見出し → 題 → 期間の範囲（板 03）
    private var cover: some View {
        ZStack(alignment: .bottomLeading) {
            if let cover = trip.cover {
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
            VStack(alignment: .leading, spacing: 8) {
                // 眉ラベル。**写真の上なので白**（板は真鍮だが、真鍮は夕日の
                // 写真の上で読めなくなる・`BrandPalette` の規則）
                Text(L("TRIP BOOK · 自動でまとまった旅", "TRIP BOOK · Put together for you"))
                    .jpEyebrow()
                    .foregroundStyle(Color.white.opacity(0.85))
                    // 読み上げは「旅の一冊」（「トリップブック」と英語で読ませない）
                    .accessibilityLabel(L("旅の一冊 · 自動でまとまった旅", "Trip book · Put together for you"))
                Text(TripBook.title(of: trip))
                    .font(JPFont.display(44, relativeTo: .largeTitle))
                    .foregroundStyle(WebTheme.foreground)
                    .shadow(color: Color.black.opacity(0.5), radius: 7, y: 2)
                Text("\(TripBook.dateRange(from: trip.start, to: trip.end)) · \(TripBook.daysLabel(trip.days))")
                    .font(JPFont.mono(12, relativeTo: .caption))
                    .foregroundStyle(WebTheme.muted)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: - 数字

    /// 枚・撮影地・移動（直線）の3枠（板 03）。距離は**写真の座標を直線で
    /// つないだ合計**で、道のりではない（`TravelDistance`）。だから札は「直線」
    private var stats: some View {
        HStack(spacing: 1) {
            statCell("\(trip.photos.count)", unit: nil, label: L("枚", "Photos"))
            statCell("\(TripBook.placeCount(of: trip.photos))", unit: nil, label: L("撮影地", "Places"))
            statCell(TripBook.distanceText(distance), unit: distance == nil ? nil : "km",
                     label: L("移動（直線）", "Distance (straight)"))
        }
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        // 3枠を1つの要素に（読み上げは「12 枚、3 撮影地、…」と続けて読む）。
        // スクリーンショットの `31-旅の足取り` がルート図の無い旅で代わりに探す
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trips.stats")
    }

    /// 升1つ。形はストーリーの反応（`StoryInsightsView.countCell`）と同じ板の部品
    private func statCell(_ value: String, unit: String?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(JPFont.mono(18, relativeTo: .title3))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit)
                        .font(JPFont.mono(12, relativeTo: .caption2))
                        .foregroundStyle(WebTheme.muted2)
                }
            }
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(WebTheme.faint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Self.cellColor)
    }

    // MARK: - ルート図

    /// 点線でつないだ足取り（板 03 の「たどった場所」）。
    /// **2か所以上のときだけ**出す（`TripBook.routeStops`）
    @ViewBuilder
    private var route: some View {
        let stops = TripBook.sampledStops(TripBook.routeStops(of: trip))
        if !stops.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("たどった場所", "Where you went"))
                    .font(.system(size: 12, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(WebTheme.faint)
                    .padding(.horizontal, 4)
                // 「ROUTE」の行は図の上に別の行として置く（図の中に重ねると、
                // 大きな字で上の札とぶつかる）
                VStack(alignment: .leading, spacing: 0) {
                    Text("ROUTE · \(TripBook.distanceText(distance))\(distance == nil ? "" : " km")")
                        .font(JPFont.mono(12, relativeTo: .caption))
                        .tracking(1.5)
                        .foregroundStyle(WebTheme.placeholder)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                    GeometryReader { proxy in
                        routeDrawing(stops, width: proxy.size.width)
                    }
                    .frame(height: TripRouteLayout.height(labelHeight: routeLabelHeight))
                }
                .background(Self.cellColor, in: RoundedRectangle(cornerRadius: 14))
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
            // 太い淡い帯の上に、真鍮の点線（板 03）
            line.stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            line.stroke(WebTheme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 5]))
            ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                let point = points[index]
                let label = layout.labels[index]
                let isLast = index == stops.count - 1
                // 終点だけ塗る（どこで旅が終わったか）
                Circle()
                    .fill(isLast ? WebTheme.accent : Self.cellColor)
                    .overlay(Circle().strokeBorder(WebTheme.accent, lineWidth: 2))
                    .frame(width: TripRouteLayout.dot, height: TripRouteLayout.dot)
                    .position(x: point.x, y: point.y)
                // 低い点は下に、高い点は上に札を出す（線と重ねない）。
                // 2行にして地名に札の幅を丸ごと使う（1行に「DAY n · 」と並べると地名がほぼ切れた）
                VStack(spacing: 0) {
                    Text("DAY \(stop.day)")
                        .font(JPFont.mono(12, relativeTo: .caption))
                    Text(stop.place)
                        .font(.caption)
                }
                .foregroundStyle(WebTheme.muted2)
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
    private var pages: some View {
        VStack(alignment: .leading, spacing: 36) {
            ForEach(TripBook.days(of: trip), id: \.number) { day in
                VStack(alignment: .leading, spacing: 20) {
                    dayHeader(day)
                    ForEach(day.photos) { photo in
                        page(photo, dayPlace: day.place)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 28)
    }

    private func dayHeader(_ day: TripBook.Day) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("DAY \(day.number)")
                .jpEyebrow()
                .accessibilityLabel(Self.spokenDay(day.number))
                .foregroundStyle(WebTheme.accent)
            Text(TripBook.monthDay(day.date))
                .font(JPFont.mono(12, relativeTo: .caption))
                .foregroundStyle(WebTheme.muted2)
            if !day.place.isEmpty {
                Text(day.place)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func page(_ photo: Photo, dayPlace: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                // 旅の一冊は自分の写真だけ（`TripBook.shelfTrips(from: myPhotos)`）。
                // 投稿直後の写真は個別ページがまだ無い（`PhotoLink`）ので、公開一覧に
                // 載っているかで決める（`isPublic`）
                PhotoDetailView(photo: photo, fromPublicFeed: isPublic(photo), context: trip.photos)
            } label: {
                RemoteImage(url: photo.detailImageURL, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            if !photo.displayTitle.isEmpty {
                Text(photo.displayTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(WebTheme.foreground)
            }
            if let first = photo.paragraphs.first {
                Text(first)
                    .font(.callout)
                    .lineSpacing(4)
                    .foregroundStyle(Color.white.opacity(0.8))
            }
            // 撮影地は**段の頭と違うときだけ**（同じ地名を毎枚くり返さない）
            if let place = photo.location?.trimmingCharacters(in: .whitespacesAndNewlines),
               !place.isEmpty, place != dayPlace {
                Text(place)
                    .font(.caption)
                    .foregroundStyle(WebTheme.faint)
            }
            // その日に聴いていた曲（付けてあれば）
            if let song = photo.song {
                SongRow(song: song)
            }
        }
    }

    // MARK: - 計算

    /// 移動（直線）。数えられなければ nil（枠には「—」）
    private var distance: Double? { TravelDistance.countableTotal(of: trip.photos, timeZone: trip.timeZone) }

    /// 数の升・ルート図の地（板の `#0b0b0c`）
    private static let cellColor = Color(red: 0x0B / 255.0, green: 0x0B / 255.0, blue: 0x0C / 255.0)

    /// 読み上げの「何日目」。**見た目の「DAY n」をそのまま読ませない**
    /// ——日本語の読み上げでは「ディーエーワイ」「デイ」になり、何の数か伝わらない
    nonisolated static func spokenDay(_ number: Int) -> String {
        L("\(number)日目", "Day \(number)")
    }

    /// ルート図の読み上げ（「1日目 金沢、2日目 富山」）
    nonisolated static func routeSpokenLabel(_ stops: [TripBook.RouteStop]) -> String {
        stops.map { "\(spokenDay($0.day)) \($0.place)" }.joined(separator: L("、", ", "))
    }
}
