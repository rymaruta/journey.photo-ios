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
///
/// **v2（2026-10-14・板 LightAlert）**: 眉ラベルは真鍮＋消えていく線（`JPEyebrowLine`）。札は v2 の札の地
/// （`WebTheme.card`）・角 14・内側 12、場所の名前は明朝（段の下限 18）、2行目に「いつ · 天気」（13・text-2・
/// 等幅の数字）、3行目に見込みの札（見込み「高」は真鍮の塗りに墨、ほかは線）。開いた中の2つは
/// 「撮影スポットを見る」（白 8% のカプセル）と「経路 ↗」（真鍮の線・外へ出る）。空・読めないは土台の
/// 状態の型（`EmptyState`・`ErrorBanner`）
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
            VStack(alignment: .leading, spacing: LightForecastStyle.cardSpacing) {
                JPEyebrowLine(L("行きたい場所の光（今週）", "Light at your wishlist places (this week)"))
                content
            }
            .padding(.horizontal, JPSpace.gutter)
            .padding(.top, JPSpace.xs)
            .padding(.bottom, JPSpace.section)
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
                HStack(spacing: JPSpace.s) {
                    thumbnail(spot?.photo, tone: card.tone)
                    VStack(alignment: .leading, spacing: 3) {
                        // 板 v2: 場所の名前は明朝（板は 16 だが、明朝の下限 18 で出す）
                        Text(card.name)
                            .font(JPFont.rowTitle)
                            .foregroundStyle(WebTheme.text)
                            .lineLimit(2)
                        // 板 v2: 「いつ · 天気」を1行に（13・text-2・数字は等幅）
                        Text(LightForecastStyle.whenLine(card))
                            .font(JPFont.mono(JPTypeScale.footnote, relativeTo: .footnote))
                            .foregroundStyle(WebTheme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                        if !card.kind.isEmpty {
                            chanceChip(card.kind, high: card.chance == .high)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // 開閉の印（形で見せる・色だけにしない）。開けない札には置かない
                    if opens {
                        Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(WebTheme.text3)
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
        .padding(JPSpace.s)
        .background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.m))
        .overlay(
            RoundedRectangle(cornerRadius: JPRadius.m)
                .strokeBorder(card.isBest ? WebTheme.accent : WebTheme.line,
                              lineWidth: card.isBest ? LightForecastStyle.bestBorder : JPStroke.hairline)
        )
    }

    /// 見込みの札（板 v2 の `.k`: 12 semibold・角丸 9）。**「高」は真鍮の塗りに墨、ほかは白 14% の線に text-2**。
    /// 色だけで伝えない——札の字そのものが「見込み高」と言う
    private func chanceChip(_ text: String, high: Bool) -> some View {
        Text(text)
            .font(JPFont.caption.weight(.semibold))
            .foregroundStyle(high ? WebTheme.accentText : WebTheme.text2)
            .lineLimit(1)
            .padding(.horizontal, JPSpace.xs)
            .padding(.vertical, 1)
            .background(high ? WebTheme.accent : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(high ? Color.clear : WebTheme.line, lineWidth: JPStroke.hairline))
            .padding(.top, 2)
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
        .clipShape(RoundedRectangle(cornerRadius: JPRadius.s))
        .accessibilityHidden(true)
    }

    /// 開いた札の下の2つ（板 v2）: 「撮影スポットを見る」（頁へ積む・白 8% のカプセル）と
    /// 「経路 ↗」（Apple のマップ・外へ出るリンクは真鍮の線と字）。経路は座標のあるスポットだけ。当たりは 44pt
    private func spotLinks(_ spot: OfficialSpot, cardId: String) -> some View {
        HStack(spacing: JPSpace.xs) {
            NavigationLink {
                // 写真の一覧はこの画面に無い。「この場所の写真（0）まだありません」を言わせない
                OfficialSpotView(spot: spot, spots: index, photos: [], photosKnown: false)
            } label: {
                linkPill(title: L("撮影スポットを見る", "See photo spot"), outward: false)
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
                    linkPill(title: openingDirections == cardId ? L("開いています…", "Opening…") : L("経路 ↗", "Directions ↗"),
                             outward: true)
                }
                .buttonStyle(.plain)
                .disabled(openingDirections != nil)
                .accessibilityLabel(L("\(spot.name)への経路", "Directions to \(spot.name)"))
                .accessibilityHint(L("Apple のマップで開きます", "Opens in Apple Maps"))
                .accessibilityIdentifier("lightForecast.directions")
            }
        }
    }

    /// 開いた札の中のカプセル（板 v2）。中へ進む方は白 8% の地に白の字、外へ出る方は真鍮 60% の線に真鍮の字。
    /// 板の見た目は 40 だが、押せるものは 44（`JPHeight.secondaryButton`）
    private func linkPill(title: String, outward: Bool) -> some View {
        Text(title)
            .font(JPFont.bodyEmphasis)
            .foregroundStyle(outward ? WebTheme.accent : WebTheme.text)
            .lineLimit(1)
            .minimumScaleFactor(WebTheme.minimumScale(forTextSize: 15))
            .padding(.horizontal, JPSpace.m)
            .frame(maxWidth: outward ? nil : .infinity, minHeight: JPHeight.secondaryButton)
            .frame(minWidth: outward ? LightForecastStyle.directionsMinWidth : nil)
            .background(outward ? Color.clear : Color.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(outward ? WebTheme.accent.opacity(0.6) : Color.clear,
                                            lineWidth: JPStroke.hairline))
            .contentShape(Capsule())
    }

    /// 札の中に開く7日（日ごとに 朝焼け・夕焼け・夜景）
    private func weekView(_ week: [LightForecastText.DayLine]) -> some View {
        VStack(alignment: .leading, spacing: JPSpace.s) {
            JPCardDivider()
            ForEach(week) { day in
                VStack(alignment: .leading, spacing: JPSpace.xxs) {
                    Text(day.title)
                        .font(JPFont.footnote.weight(.semibold))
                        .foregroundStyle(WebTheme.text)
                    ForEach(Array(day.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: JPSpace.xs) {
                            Text(item.event)
                                .font(JPFont.meta)
                                .foregroundStyle(WebTheme.text3)
                                .frame(minWidth: 110, alignment: .leading)
                            Text(item.outlook)
                                .font(item.chance == .high ? JPFont.caption.weight(.semibold) : JPFont.caption)
                                .foregroundStyle(item.chance == .high ? WebTheme.text : WebTheme.text2)
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
                .font(JPFont.caption)
                .lineSpacing(3)
                .foregroundStyle(WebTheme.text3)
                .fixedSize(horizontal: false, vertical: true)
            // Apple Weather の出典（Apple が表示を求めている）。黒地の上の外へ出るリンクは真鍮（CLAUDE.md）
            Link(destination: forecast.attribution.legalURL) {
                Text(L("天気: \(forecast.attribution.serviceName) · データの出典",
                       "Weather: \(forecast.attribution.serviceName) · Data sources"))
                    .font(JPFont.caption)
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

    /// 空（v2 の板 LightAlert の「空」: 細い線の絵 → 明朝 20 の見出し → 説明）。並びは土台の `EmptyState`
    private func emptyView(_ empty: LightForecastText.Empty) -> some View {
        VStack(spacing: 0) {
            stateIcon("sun.horizon")
            EmptyState(title: LightForecastText.emptyTitle(empty), message: LightForecastText.emptyBody(empty))
        }
        .padding(.top, JPSpace.section)
    }

    /// 読めなかった（Pro でない・予報を読めない・圏外）。Pro でないのは失敗ではないので `EmptyState`
    /// （一手は写真の無い画面の主ボタン＝真鍮の塗り）、読めなかった回は `ErrorBanner`（「もう一度」）
    @ViewBuilder
    private func failureView(_ failure: LightForecastText.Failure) -> some View {
        switch failure {
        case .notPro:
            VStack(spacing: 0) {
                stateIcon("sparkles")
                EmptyState(title: LightForecastText.failureTitle(failure),
                           message: LightForecastText.failureBody(failure),
                           actionTitle: L("Pro について見る", "About Pro"),
                           actionIdentifier: "lightForecast.paywall") {
                    deliveredAtPaywall = store.deliveredRevision
                    showPaywall = true
                }
            }
            .padding(.top, JPSpace.section)
        case .signedOut:
            VStack(spacing: 0) {
                stateIcon("cloud.sun")
                EmptyState(title: LightForecastText.failureTitle(failure), message: LightForecastText.failureBody(failure))
            }
            .padding(.top, JPSpace.section)
        case .unavailable, .unreachable, .other:
            ErrorBanner(title: LightForecastText.failureTitle(failure),
                        message: LightForecastText.failureBody(failure)) {
                Task { await load() }
            }
            .padding(.top, JPSpace.section)
        }
    }

    /// 状態の上の細い線の絵（板 v2: 44・線 1・灰）。飾りなので読み上げない
    private func stateIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 36, weight: .ultraLight))
            .foregroundStyle(WebTheme.text3)
            .accessibilityHidden(true)
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

/// 光と天気の知らせの見た目（v2 の板 LightAlert・2026-10-14）。テストで見張る
enum LightForecastStyle {
    /// 札と札の間（板: 10。物差しの 8 と 12 の間なので 12 に寄せた）
    static let cardSpacing: CGFloat = JPSpace.s
    /// いちばん良い札の真鍮の縁（板: 1.5）
    static let bestBorder: CGFloat = 1.5
    /// 「経路 ↗」の最小の幅（板: 96）
    static let directionsMinWidth: CGFloat = 96

    /// 札の2行目「明日 · 日の出 5:42 · 晴れ」（v1 は天気を右上に分けていた）。予報の無い場所は「… · 予報なし」
    static func whenLine(_ card: LightForecastText.Card) -> String {
        [card.when, card.weather].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
