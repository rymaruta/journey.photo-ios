import SwiftUI

/// 光と天気の知らせ（Pro・デザインの板 LightAlert・2026-10-09）。「行きたい場所の光（今週）」の一覧。
///
/// 入口は2つ: 設定の Pro の節の「光と天気の知らせ」と、前の晩 20:00 のプッシュ（`type: "light"`・
/// お知らせの画面の上に積む `NotificationsViewModel.Route.light`）。
///
/// 板のとおり:
/// - 眉ラベル「行きたい場所の光（今週）」（真鍮・黒地の上の合図）
/// - 場所ごとの札（地 #121212・角 14）: 左に色の四角 56pt（角 10）、名前（14 太字）といつ（12・白65%）、
///   右に天気（13 太字）と見込み（12・白60%）。いちばん良いもの（見込み「高」のいちばん早い1枚）は真鍮 1.5pt の縁、
///   ほかは #222 の 1pt
/// - 注記（12・板の文言）
///
/// 板に無くて足したもの:
/// - **Apple Weather の出典**（Apple が表示を求めている）。注記の下に、応答の出典のリンク（真鍮・外へ出るリンク）
/// - 札を押すと、その場所の7日（朝焼け・夕焼け・夜景）を札の中に開く（応答は7日ぶん持っている）。
///   開閉の印（› 閉じている / ⌄ 開いている）を右端に置く（2026-10-11・押せると分からなかった）
/// - 開いた中に「スポットを見る」（撮影スポットの頁）と「経路」（Apple のマップ）の行（2026-10-11・
///   以前は週の予報が開くだけの行き止まりだった）。撮影スポットは索引から slug で引く（`LightForecastText.spot`）
/// - 空のとき（行きたい場所が無い／撮影スポットが無い）・読めなかったとき（Pro でない・予報を読めない・圏外）
///
/// **四角はスポットの写真（2026-10-11）。** 応答は写真を持たないので、撮影スポットの索引の代表写真
/// （Wikimedia Commons）を引いて出す（マイページの行きたい場所の行と同じ 56pt・角 10・`SpotThumbImage`。
/// 出典は開いた先のスポットの頁に出る＝行きたい場所の行と同じ扱い）。写真が引けない場所だけ、
/// 板の4色を見込みの種類（朝焼け・夕焼け・夜景・低）に当てた四角（板の見本の4枚がちょうどその4つ）
struct LightForecastView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var store: StoreService

    private enum Phase: Equatable {
        case loading
        case loaded(LightForecast)
        case failed(LightForecastText.Failure)
    }

    @State private var phase: Phase = .loading
    /// 開いている札（場所の鍵）
    @State private var expanded: Set<String> = []
    @State private var showPaywall = false
    @State private var deliveredAtPaywall = 0
    /// 一覧の「今日・明日」を決める時刻（読み込んだとき）
    @State private var loadedAt = Date()
    /// 撮影スポットの索引（札の写真・「スポットを見る」「経路」に使う）。読めなければ空のまま（札は色の四角）
    @State private var index: [OfficialSpot] = []
    /// 「経路」を探している札（連打で2つ開かない）・その仕事（画面を離れたら取り消す）
    @State private var openingDirections: String?
    @State private var directionsTask: Task<Void, Never>?
    /// 画面が出ているか（「経路」を探している間に離れたら開かない。「スポットを見る」で積んだときも離れた扱い）
    @State private var onScreen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("行きたい場所の光（今週）", "Light at your wishlist places (this week)"))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                    .accessibilityAddTraits(.isHeader)
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .webScreen()
        .navigationTitle(L("光と天気の知らせ", "Light & weather alerts"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        // 札の場所が決まったら、その撮影スポット（写真・座標）を引く
        .task(id: placesKey) {
            guard case .loaded(let forecast) = phase else { return }
            await loadSpots(for: forecast)
        }
        .refreshable { await load(refreshing: true) }
        .onAppear { onScreen = true }
        .onDisappear {
            onScreen = false
            directionsTask?.cancel()
        }
        .fullScreenCover(isPresented: $showPaywall, onDismiss: {
            // 案内で Pro になったら読み直す（`NameSideBadgeView` と同じ見分け方）
            guard store.deliveredRevision != deliveredAtPaywall else { return }
            Task { await load() }
        }) {
            PaywallView()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView()
                .tint(WebTheme.muted2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        case .failed(let failure):
            failureView(failure)
        case .loaded(let forecast):
            if forecast.places.isEmpty {
                emptyView(LightForecastText.empty(wishlist: wishlist.spotIds))
            } else {
                let byKey = Dictionary(forecast.places.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
                ForEach(LightForecastText.cards(forecast, now: loadedAt)) { card in
                    cardView(card, place: byKey[card.id])
                }
            }
            footer(forecast)
        }
    }

    // MARK: - 札

    private func cardView(_ card: LightForecastText.Card, place: LightForecast.Place?) -> some View {
        let isOpen = expanded.contains(card.id)
        let week = place.map { LightForecastText.week($0, now: loadedAt) } ?? []
        let spot = place.flatMap { LightForecastText.spot(for: $0, in: index) }
        // 開いて出すものがあるときだけ開ける（週の予報か、スポットへの行）
        let opens = !week.isEmpty || spot != nil
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                guard opens else { return }
                if isOpen { expanded.remove(card.id) } else { expanded.insert(card.id) }
            } label: {
                HStack(spacing: 12) {
                    thumbnail(spot?.photo, tone: card.tone)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(card.name)
                            .font(JPFont.number(14, weight: .bold, relativeTo: .subheadline))
                            .foregroundStyle(WebTheme.text)
                            .lineLimit(2)
                        Text(card.when)
                            .font(JPFont.mono(12))
                            .foregroundStyle(Color.white.opacity(0.65))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(card.weather)
                            .font(JPFont.number(13, weight: .bold, relativeTo: .footnote))
                            .foregroundStyle(WebTheme.text)
                        if !card.kind.isEmpty {
                            Text(card.kind)
                                .font(.caption)
                                .foregroundStyle(WebTheme.faint)
                        }
                    }
                    .multilineTextAlignment(.trailing)
                    // 開閉の印（形で見せる・色だけにしない）。開けない札には置かない
                    if opens {
                        Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(WebTheme.faint)
                            .frame(width: 14)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(card.accessibilityLabel)
            .accessibilityValue(opens ? LightForecastText.disclosureValue(isOpen: isOpen) : "")
            .accessibilityHint(!opens ? "" : (isOpen ? L("今週の光を閉じます", "Hides this week")
                                                  : L("今週の光を開きます", "Shows this week")))
            .accessibilityIdentifier("lightForecast.card")

            if isOpen {
                if !week.isEmpty {
                    weekView(week)
                }
                if let spot {
                    spotLinks(spot, cardId: card.id)
                }
            }
        }
        .padding(14)
        .background(Color(red: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(card.isBest ? WebTheme.accent : Color(red: 0x22 / 255, green: 0x22 / 255, blue: 0x22 / 255),
                              lineWidth: card.isBest ? 1.5 : 1)
        )
    }

    /// 札の左の四角。スポットの写真があれば写真、無ければ見込みの種類の色（板の4色）
    @ViewBuilder
    private func thumbnail(_ photo: SpotImage?, tone: LightForecastText.Tone) -> some View {
        Group {
            if let photo {
                // 56pt の枠なので縮めて読む（マイページの行きたい場所の行と同じ読み方）
                SpotThumbImage(image: photo, assumedRatioLimit: 2)
            } else {
                Self.color(tone.hex)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
    }

    /// 開いた札の下の行: 「スポットを見る」（頁へ積む・白）と「経路」（Apple のマップ・外へ出るリンクは真鍮）。
    /// 経路は座標のあるスポットだけ。当たりは 1行全体で 44pt
    private func spotLinks(_ spot: OfficialSpot, cardId: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            NavigationLink {
                // 写真の一覧はこの画面に無い。「この場所の写真（0）まだありません」を言わせない
                OfficialSpotView(spot: spot, spots: index, photos: [], photosKnown: false)
            } label: {
                linkRow(icon: "mappin.and.ellipse", title: L("スポットを見る", "See spot"),
                        tint: WebTheme.foreground, trailing: "chevron.right")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("lightForecast.openSpot")
            if let coords = spot.coords {
                Button {
                    guard openingDirections == nil else { return }
                    openingDirections = cardId
                    let name = spot.name
                    directionsTask = Task { @MainActor in
                        defer { openingDirections = nil }
                        await SpotDirections.openDirections(name: name, coords: coords, stillWanted: { onScreen })
                    }
                } label: {
                    linkRow(icon: "arrow.triangle.turn.up.right.diamond",
                            title: openingDirections == cardId ? L("開いています…", "Opening…") : L("経路", "Directions"),
                            tint: WebTheme.accent, trailing: "arrow.up.right")
                }
                .buttonStyle(.plain)
                .disabled(openingDirections != nil)
                .accessibilityLabel(L("\(spot.name)への経路", "Directions to \(spot.name)"))
                .accessibilityHint(L("Apple のマップで開きます", "Opens in Apple Maps"))
                .accessibilityIdentifier("lightForecast.directions")
            }
        }
    }

    private func linkRow(icon: String, title: String, tint: Color, trailing: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Image(systemName: trailing)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WebTheme.faint)
                .accessibilityHidden(true)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// 札の中に開く7日（日ごとに 朝焼け・夕焼け・夜景）
    private func weekView(_ week: [LightForecastText.DayLine]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            ForEach(week) { day in
                VStack(alignment: .leading, spacing: 4) {
                    Text(day.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WebTheme.muted)
                    ForEach(Array(day.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.event)
                                .font(JPFont.mono(12))
                                .foregroundStyle(WebTheme.faint)
                                .frame(minWidth: 110, alignment: .leading)
                            Text(item.outlook)
                                .font(item.chance == .high ? .caption.weight(.semibold) : .caption)
                                .foregroundStyle(item.chance == .high ? WebTheme.text : WebTheme.muted2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    // MARK: - 注記・出典

    private func footer(_ forecast: LightForecast) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LightForecastText.note(forecast))
                .font(.caption)
                .lineSpacing(3)
                .foregroundStyle(WebTheme.faint)
                .fixedSize(horizontal: false, vertical: true)
            // Apple Weather の出典（Apple が表示を求めている）。黒地の上の外へ出るリンクは真鍮（CLAUDE.md）
            Link(destination: forecast.attribution.legalURL) {
                Text(L("天気: \(forecast.attribution.serviceName) · データの出典",
                       "Weather: \(forecast.attribution.serviceName) · Data sources"))
                    .font(.caption)
                    .foregroundStyle(WebTheme.accent)
                    .underline()
                    .frame(minHeight: WebTheme.minTapTarget, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("lightForecast.attribution")
        }
        .padding(.top, 4)
    }

    // MARK: - 空・読めない

    private func emptyView(_ empty: LightForecastText.Empty) -> some View {
        message(icon: "sun.horizon",
                title: LightForecastText.emptyTitle(empty),
                body: LightForecastText.emptyBody(empty))
    }

    @ViewBuilder
    private func failureView(_ failure: LightForecastText.Failure) -> some View {
        VStack(spacing: 20) {
            message(icon: failure == .notPro ? "sparkles" : "cloud.sun",
                    title: LightForecastText.failureTitle(failure),
                    body: LightForecastText.failureBody(failure))
            switch failure {
            case .notPro:
                // 写真の無い画面の主ボタンは真鍮の塗りに墨（CLAUDE.md）
                Button {
                    deliveredAtPaywall = store.deliveredRevision
                    showPaywall = true
                } label: {
                    Text(L("Pro について見る", "About Pro")).jpPillButton(.accent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("lightForecast.paywall")
            case .signedOut:
                EmptyView()
            case .unavailable, .unreachable, .other:
                Button { Task { await load() } } label: {
                    Text(Labels.Common.retry).jpPillButton(.outline)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func message(icon: String, title: String, body: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(WebTheme.faint)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(WebTheme.foreground)
                .multilineTextAlignment(.center)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(WebTheme.muted2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - 読み込み

    private func load(refreshing: Bool = false) async {
        if let preview = LightForecastText.preview {
            // 見本は索引の本物のスポット（写真・座標のある行）の名前で組む（写真と行が出る絵を撮る）
            if preview == .sample { await loadIndexIfNeeded() }
            loadedAt = Date()
            phase = .loaded(preview == .sample
                            ? LightForecastText.sample(now: loadedAt, spots: LightForecastText.previewSpots(index))
                            : LightForecast(places: []))
            return
        }
        // 引っぱって読み直すときは、出ている一覧を残したまま読む
        if !refreshing { phase = .loading }
        do {
            let forecast = try await LightForecastService(api: environment.api).fetch()
            loadedAt = Date()
            phase = .loaded(forecast)
        } catch {
            // 取り消し（画面を閉じた）は何も出さない
            if Task.isCancelled { return }
            // 読み直しが圏外で失敗しても、出ている一覧は消さない
            if refreshing, case .loaded = phase { return }
            phase = .failed(LightForecastText.failure(for: error))
        }
    }

    /// 札の場所（`.task(id:)` の鍵）。場所が変わったときだけ撮影スポットを引き直す
    private var placesKey: String {
        guard case .loaded(let forecast) = phase else { return "" }
        return forecast.places.map(\.slug).joined(separator: "|")
    }

    private func loadIndexIfNeeded() async {
        guard index.isEmpty, let fetched = try? await environment.spots.fetchIndex(),
              !Task.isCancelled else { return }
        index = fetched
    }

    /// 札の場所の撮影スポットを引く。索引だけの行（分けた置き場）なら、写真のある詳細を重ねる
    /// （`OfficialSpotService.withDetails`）。読めなければ札は色の四角のまま
    private func loadSpots(for forecast: LightForecast) async {
        await loadIndexIfNeeded()
        let needed = forecast.places.compactMap { LightForecastText.spot(for: $0, in: index) }
        guard !Task.isCancelled, needed.contains(where: \.isIndexOnly) else { return }
        let merged = await environment.spots.withDetails(index, for: needed)
        guard !Task.isCancelled else { return }
        index = merged
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }
}
