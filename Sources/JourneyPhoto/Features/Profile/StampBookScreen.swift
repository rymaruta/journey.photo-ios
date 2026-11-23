import SwiftUI

// MARK: - 入口（1つの部品）

/// 旅のスタンプ帳の入口（札 #712）。**行の中身と行き先をここ1つにまとめる**——マイページの荷札の列（札 #714・`StampBookToolTag`）と
/// メニューの「旅の楽しみ」の行が、同じ行き先と最近の3つを使う。
/// 2026-11-23 判断: とおまわり号の行（札 #709 で消した）があった所に置く。入口の数は前と同じ
enum StampBookEntry {
    static var title: String { StampBookText.title }
    static var detail: String { StampBookText.entryDetail }
    /// 印（二重の丸＝スタンプの枠。案の頁の模型の印と同じ形）
    static let systemImage = "circle.circle"

    /// 行き先
    @MainActor static func destination() -> some View { StampBookScreen() }
    /// 押せないボタンの濃さ
    static let disabledOpacity = 0.4
}

extension StampBookEntry {
    /// 行の右に出す最近の3つ（案の頁の4）。帳面がまだ無い・空なら出さない。荷札の列（札 #714）も同じ部品を使う
    @MainActor static func recentAccessory(_ book: StampBook?) -> AnyView? {
        guard let book, recentCount(book) != nil else { return nil }
        return AnyView(StampBookRecentMarks(stamps: book.recent))
    }

    /// 最近の3つの読み上げ（荷札の値）。出さないときは空
    static func recentAccessibility(_ book: StampBook?) -> String {
        guard let book, recentCount(book) != nil else { return "" }
        return StampBookText.recentAccessibility(book.recent.prefix(3).map(\.name))
    }

    /// 行の右に出す数（1〜3）。出さないなら nil
    static func recentCount(_ book: StampBook?) -> Int? {
        guard let book, !book.isEmpty else { return nil }
        return book.recent.count
    }
}

/// マイページの旅の道具の荷札（`TripToolTag`・札 #714 の列）。名前の右に最近の3つ。
/// 2026-11-23 判断（1.2.0 の統合）: #712 の縦の行（`JPRowLabel`）は、#714 で道具の入口が横に送る荷札の列になったので荷札にした。
/// 荷札の名前は「スタンプ帳」（`TripTool.stampBook.title`）、開いた画面の題は「旅のスタンプ帳」（`StampBookEntry.title`）。
/// **帳面を見張るのはこの札の中だけ**（マイページ全体を描き直さない・`MyPageTrunkRow` と同じ）
struct StampBookToolTag: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @ObservedObject private var model = StampBookModel.shared

    var body: some View {
        NavigationLink { StampBookEntry.destination() } label: {
            TripToolTag(title: TripTool.stampBook.title,
                        accessory: StampBookEntry.recentAccessory(model.book))
        }
        .buttonStyle(TripToolTagStyle())
        .modifier(TripToolTapFeedback())
        // 荷札は中の絵を読み上げないので、最近の3つは値で言う（縦の行のときと同じ文）
        .accessibilityValue(StampBookEntry.recentAccessibility(model.book))
        .accessibilityIdentifier(TripTool.stampBook.identifier)
        // この起動でまだ作っていないときだけ読む（マイページを開くたびには読まない）
        .task(id: auth.userId) { await model.loadIfNeeded(userId: auth.userId, environment: environment) }
    }
}

/// メニューの「旅の楽しみ」の行（`SiteMenuRow` の形）。右に最近の3つ
struct StampBookMenuRow: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @ObservedObject private var model = StampBookModel.shared

    var body: some View {
        NavigationLink { StampBookEntry.destination() } label: {
            SiteMenuRow(title: StampBookEntry.title, systemImage: StampBookEntry.systemImage, note: StampBookEntry.detail,
                        accessory: StampBookEntry.recentAccessory(model.book))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("menu.stampBook")
        .task(id: auth.userId) { await model.loadIfNeeded(userId: auth.userId, environment: environment) }
    }
}

// MARK: - 読み込み

/// 帳面を作る係（1つだけ・`shared`）。自分の写真・観光スポットの索引・結びの表・突き合わせの索引を読んで、端末で作る（保存しない）。
/// スタンプ帳の画面と入口の行（最近の3つ）が同じものを見る。
///
/// 2026-11-23 判断（確かめ役の指摘・重さ）:
/// - 突き合わせの下ごしらえ（`SpotMatcher(index:)`・約 4,640 行）と帳面づくりは、画面の処理（メインスレッド）の外で
/// - 画面を閉じたら（呼んだ側の Task が止まったら）作りかけを捨てる。途中で止める合図を見る（`buildCancellable`）
/// - 前回と同じ材料（`StampBook.fingerprint`）なら作り直さない。作り終えた結果は、閉じたあとでも覚える
@MainActor
final class StampBookModel: ObservableObject {
    enum Phase: Equatable {
        case loading, loaded, failed
        /// ログインしていない（失敗の文は出さない）
        case signedOut
    }

    static let shared = StampBookModel()

    @Published private(set) var book: StampBook?
    @Published private(set) var phase: Phase = .loading
    /// 観光スポットの索引（県のページの「まだの観光スポット」と、1つのスタンプの「観光スポットを見る」で使う）
    @Published private(set) var spots: [OfficialSpot] = []
    /// 圏外で、前に読めた帳面を出している（上に一行出す）
    @Published private(set) var showingSaved = false

    /// 同じ起動の間だけ覚える前回の帳面と材料の目印（開き直したとき・圏外のときにすぐ出す）。1人分だけ。端末には書かない
    private var memory: (userId: String, fingerprint: Int, book: StampBook, spots: [OfficialSpot])?
    private var running: (userId: String, task: Task<Void, Never>)?

    /// 退会・ログアウトで前の人の帳面を残さない
    static func forget() { shared.reset() }

    private func reset() {
        running?.task.cancel()
        running = nil
        memory = nil
        pressedThisLaunch = nil
        book = nil
        spots = []
        phase = .loading
        showingSaved = false
    }

    /// 投稿の直後の判定（`StampMoment.pressed`）に渡す、前の帳面。この起動でまだ作っていなければ nil
    func knownBook(userId: String?) -> StampBook? {
        guard let userId, let memory, memory.userId == userId else { return nil }
        return memory.book
    }

    /// この起動で、投稿の直後に押したと知らせた観光スポット（帳面を作り直すまでに同じ所で2回祝わない）
    private var pressedThisLaunch: (userId: String, spotIds: Set<String>)?

    /// 投稿の直後に押されたスタンプ（`StampMoment.pressed`）。前の帳面と索引はこの起動で作ったもの（無ければ nil＝出さない）。
    /// 帳面は投稿のあとすぐには作り直さないので、**この起動で知らせた所は覚えて2回目は出さない**（2026-11-23 判断・1.2.0 の統合）
    func pressed(spotIds: [String], userId: String?, now: Date = Date()) -> StampMoment.Pressed? {
        guard let userId, let memory, memory.userId == userId else { return nil }
        let told = pressedThisLaunch?.userId == userId ? pressedThisLaunch?.spotIds ?? [] : []
        guard let pressed = StampMoment.pressed(spotIds: spotIds.filter { !told.contains($0) }, before: memory.book,
                                                spots: memory.spots, today: StampMoment.day(now)) else { return nil }
        pressedThisLaunch = (userId, told.union([pressed.stamp.spotId]))
        return pressed
    }

    /// 入口の行から: この起動でまだ一度も作っていないときだけ読む（マイページを開くたびに読まない）
    func loadIfNeeded(userId: String?, environment: AppEnvironment) async {
        guard knownBook(userId: userId) == nil else { return }
        await load(userId: userId, environment: environment)
    }

    /// 読み直す。同じ人の読み込みが動いていれば、それを待つ（2つ同時に作らない）
    func load(userId: String?, environment: AppEnvironment) async {
        guard let userId else {
            reset()
            phase = .signedOut
            return
        }
        if let sample = PreviewSession.stampBookSample {
            book = sample
            spots = []
            phase = .loaded
            return
        }
        if let memory, memory.userId == userId {
            book = memory.book
            spots = memory.spots
            phase = .loaded
        } else if memory != nil {
            reset()
        }
        if let running, running.userId == userId {
            await withTaskCancellationHandler { await running.task.value } onCancel: { running.task.cancel() }
            return
        }
        let task = Task { await self.refresh(userId: userId, environment: environment) }
        running = (userId, task)
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if running?.task == task { running = nil }
    }

    private func refresh(userId: String, environment: AppEnvironment) async {
        do {
            async let photos = environment.photos.myPhotos()
            async let index = try? await environment.spots.fetchIndex()
            async let links = environment.spots.fetchPhotoLinks()
            async let match = environment.spots.fetchMatchIndex()
            let mine = try await photos
            guard let spotRows = await index else { throw StampBookLoadError.noIndex }
            let table = await links
            let matchIndex = await match
            try Task.checkCancellation()
            let key = StampBook.fingerprint(me: userId, photos: mine, spots: spotRows, links: table,
                                            matchRows: matchIndex?.rows.count)
            showingSaved = false
            if let memory, memory.userId == userId, memory.fingerprint == key {
                // 前回と同じ材料: 作り直さない
                phase = .loaded
                return
            }
            // 下ごしらえも帳面づくりも、画面の処理の外で。止める合図は外の処理へ渡す
            let job = Task.detached(priority: .userInitiated) { () throws -> StampBook in
                let matcher = matchIndex.map(SpotMatcher.init(index:))
                try Task.checkCancellation()
                return try StampBook.buildCancellable(me: userId, photos: mine, spots: spotRows, links: table,
                                                      matcher: matcher)
            }
            let built = try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
            // 作り終えた結果は覚える（閉じたあとでも次に使える）。人が替わっていたら捨てる
            guard memory == nil || memory?.userId == userId, running?.userId == userId else { return }
            memory = (userId, key, built, spotRows)
            book = built
            spots = spotRows
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            // 前に読めた帳面があれば、それを出したまま（圏外ならその旨を一行）。無ければ失敗の札
            if book == nil {
                phase = .failed
            } else {
                showingSaved = OfflineTripStore.isOffline(error)
            }
        }
    }

    private enum StampBookLoadError: Error { case noIndex }
}

// MARK: - 帳面（表紙）

/// 旅のスタンプ帳の画面（札 #712）。表紙は日本地図と県の行。押すと県のページ、スタンプを押すと1つのスタンプの札。
///
/// 状態: 読み込み中（行の骨格）・空（白い地図と点線の丸1つ、次の一手は「観光スポットを見る」1つ）・
/// 失敗（知らせと「もう一度」。前に読めた帳面があればそれを出す）・圏外（同じ起動で読めた帳面を出す）。
///
/// 2026-11-23 判断:
/// - **本人だけ**（owner）。この画面は自分の写真しか読まず、人のページからは開けない。共有の道も置かない
/// - 表紙に出す数は「押した数」と「県の数」だけ。全国の観光スポットの数のような大きすぎる分母は出さない（県のページでだけ「3 / 68」）
/// - 設定は置かない。押される条件の説明は一行だけ（空のときは見出しで言う）
struct StampBookScreen: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @ObservedObject private var model = StampBookModel.shared
    @State private var openedPrefecture: StampBookPage?
    @State private var browsing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JPSpace.m) {
                content
            }
            .padding(.horizontal, ProfileV2.gutter)
            .padding(.top, JPSpace.xs)
            .padding(.bottom, JPSpace.screenEnd)
        }
        .webScreen()
        .navigationTitle(StampBookText.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openedPrefecture) { page in
            StampBookPageView(page: page, book: model.book ?? .empty, spots: model.spots)
        }
        .navigationDestination(isPresented: $browsing) {
            OfficialSpotIndexView(scope: .all, spots: model.spots, photos: [], photosKnown: false)
        }
        .task(id: auth.userId) { await model.load(userId: auth.userId, environment: environment) }
        .accessibilityIdentifier("stampBook.screen")
    }

    @ViewBuilder
    private var content: some View {
        if model.phase == .signedOut {
            // ログインしていない（入口は本人のページにしか無いので、ふつうは来ない）。失敗の文は出さない
            EmptyView()
        } else if let book = model.book {
            if model.showingSaved {
                // 圏外: 前に読んだ帳面を出したまま、上に一行（ほかの画面の圏外の帯と同じ部品）
                JPStateBand(kind: .offline, title: StampBookText.offlineSaved,
                            actionIdentifier: "stampBook.offline.retry",
                            action: { Task { await model.load(userId: auth.userId, environment: environment) } })
                .accessibilityIdentifier("stampBook.offline")
            }
            if book.isEmpty { emptyBlock } else { cover(book) }
        } else if model.phase == .failed {
            ErrorBanner(message: StampBookText.loadFailed) {
                Task { await model.load(userId: auth.userId, environment: environment) }
            }
            .accessibilityIdentifier("stampBook.failed")
        } else {
            JPLoadingState(kind: .rows)
                .accessibilityIdentifier("stampBook.loading")
        }
    }

    private func cover(_ book: StampBook) -> some View {
        VStack(alignment: .leading, spacing: JPSpace.m) {
            StampPaper(bottom: JPSpace.xs) {
                VStack(spacing: JPSpace.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(StampBookText.japan)
                            .font(JPFont.rowTitle)
                        Spacer(minLength: JPSpace.xs)
                        counts(stamps: book.stamps.count, prefectures: book.prefectures.count)
                    }
                    .padding(.horizontal, JPSpace.xxs)
                    StampBookMap(stamped: Set(book.prefectures)) { name in
                        openedPrefecture = .prefecture(name)
                    }
                    .frame(maxWidth: 260)
                }
            }
            JPCard {
                ForEach(Array(book.prefectures.enumerated()), id: \.element) { index, name in
                    if index > 0 { JPCardDivider() }
                    prefectureRow(name, book: book)
                }
                if !book.abroad.isEmpty {
                    if !book.prefectures.isEmpty { JPCardDivider() }
                    Button { openedPrefecture = .abroad } label: {
                        JPRowLabel(title: StampBookText.abroad, value: StampBookText.countries(book.countryCount))
                    }
                    .buttonStyle(JPRowButtonStyle())
                    .accessibilityIdentifier("stampBook.row.abroad")
                }
            }
            Text(StampBookText.howTo)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    private func prefectureRow(_ name: String, book: StampBook) -> some View {
        let have = book.stamps(in: name).count
        let total = book.totals[name]
        return Button { openedPrefecture = .prefecture(name) } label: {
            JPRowLabel(title: name, value: StampBookText.ratio(have, total))
        }
        .buttonStyle(JPRowButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StampBookText.rowAccessibility(prefecture: name, have: have, total: total))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("stampBook.row.\(name)")
    }

    /// 表紙の数「10 個　4 県」。数は SF の等幅数字で大きく、単位は小さく
    private func counts(stamps: Int, prefectures: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: JPSpace.xxs) {
            Text("\(stamps)").font(JPFont.number(JPTypeScale.headline, weight: .semibold, relativeTo: .headline))
            Text(StampBookText.stampUnit(stamps)).font(JPFont.caption)
                .foregroundStyle(StampInk.swiftUIColor(StampInk.sumiSoft))
            Text("\(prefectures)").font(JPFont.number(JPTypeScale.headline, weight: .semibold, relativeTo: .headline))
                .padding(.leading, JPSpace.xs)
            Text(StampBookText.prefectureUnit(prefectures)).font(JPFont.caption)
                .foregroundStyle(StampInk.swiftUIColor(StampInk.sumiSoft))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StampBookText.countsAccessibility(stamps: stamps, prefectures: prefectures))
        .accessibilityIdentifier("stampBook.counts")
    }

    /// まだ1つも無いとき: 白い地図と点線の丸1つ。次にすることは1つだけ
    private var emptyBlock: some View {
        VStack(spacing: JPSpace.m) {
            StampPaper {
                ZStack(alignment: .bottomTrailing) {
                    StampBookMap(stamped: [])
                        .frame(maxWidth: 230)
                        .frame(maxWidth: .infinity)
                    StampEmptySlot(text: StampBookText.emptySlot)
                }
            }
            Text(StampBookText.emptyTitle)
                .font(JPFont.stateTitle)
                .foregroundStyle(WebTheme.foreground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            // 観光スポットの索引がまだ無い（見本の帳面・読めていない）間は押せない見た目にする（薄くして押せなくする）
            let browsable = !model.spots.isEmpty
            Button { browsing = true } label: {
                Text(StampBookText.browseSpots)
                    .font(JPFont.confirmButton)
                    .foregroundStyle(WebTheme.accentText)
                    .frame(maxWidth: .infinity, minHeight: JPHeight.primaryButton)
                    .background(WebTheme.accentFill, in: Capsule())
                    .contentShape(Capsule())
                    .opacity(browsable ? 1 : StampBookEntry.disabledOpacity)
            }
            .buttonStyle(.plain)
            .disabled(!browsable)
            .accessibilityIdentifier("stampBook.empty.browse")
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("stampBook.empty")
    }
}

// MARK: - 県のページ

/// 表紙から開くページ（県か海外）
enum StampBookPage: Hashable, Identifiable {
    case prefecture(String)
    case abroad

    var id: String {
        switch self {
        case .prefecture(let name): return name
        case .abroad: return "abroad"
        }
    }

    var title: String {
        switch self {
        case .prefecture(let name): return name
        case .abroad: return StampBookText.abroad
        }
    }
}

/// 県のページ（紙の上にスタンプを3つずつ並べ、最後に点線の「つぎのひとつ」）と「まだの観光スポット」
struct StampBookPageView: View {
    let page: StampBookPage
    let book: StampBook
    let spots: [OfficialSpot]

    @State private var opened: StampBook.Stamp?
    @State private var browsing = false

    private var stamps: [StampBook.Stamp] {
        switch page {
        case .prefecture(let name): return book.stamps(in: name)
        case .abroad: return book.abroad
        }
    }

    private var prefecture: String? {
        if case .prefecture(let name) = page { return name }
        return nil
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: JPSpace.xs), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JPSpace.m) {
                StampPaper(bottom: JPSpace.m) {
                    VStack(spacing: JPSpace.xs) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(page.title)
                                .font(JPFont.cardTitle)
                                .accessibilityAddTraits(.isHeader)
                            Spacer(minLength: JPSpace.xs)
                            Text(prefecture.map { StampBookText.ratio(stamps.count, book.totals[$0]) }
                                 ?? StampBookText.countries(book.countryCount))
                                .font(JPFont.mono(JPTypeScale.footnote, relativeTo: .footnote))
                                .foregroundStyle(StampInk.swiftUIColor(StampInk.sumiSoft))
                        }
                        .padding(.horizontal, JPSpace.xxs)
                        LazyVGrid(columns: columns, spacing: JPSpace.xs) {
                            ForEach(stamps) { stamp in
                                Button { opened = stamp } label: {
                                    StampView(stamp: stamp)
                                        .padding(JPSpace.xxs)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("stampBook.stamp.\(stamp.spotId)")
                            }
                            if prefecture != nil, (book.remaining(in: prefecture ?? "") ?? 1) > 0 {
                                StampEmptySlot(text: StampBookText.nextSlot)
                            }
                        }
                    }
                }
                if let prefecture, let remaining = book.remaining(in: prefecture), remaining > 0, !spots.isEmpty {
                    JPCard {
                        Button { browsing = true } label: {
                            JPRowLabel(title: StampBookText.remainingTitle, detail: StampBookText.remainingNote(prefecture),
                                       value: "\(remaining)")
                        }
                        .buttonStyle(JPRowButtonStyle())
                        .accessibilityIdentifier("stampBook.remaining")
                    }
                }
            }
            .padding(.horizontal, ProfileV2.gutter)
            .padding(.top, JPSpace.xs)
            .padding(.bottom, JPSpace.screenEnd)
        }
        .webScreen()
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $browsing) {
            if let prefecture {
                OfficialSpotIndexView(scope: .prefecture(prefecture), spots: spots, photos: [], photosKnown: false)
            }
        }
        .sheet(item: $opened) { stamp in
            StampDetailSheet(stamp: stamp, spot: spots.first { $0.spotId == stamp.spotId }, spots: spots)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .accessibilityIdentifier("stampBook.page")
    }
}

// MARK: - 1つのスタンプ

/// 1つのスタンプの札（下から出る）。大きなスタンプ・名前・はじめて撮った日・そこで撮った自分の写真・観光スポットへ
struct StampDetailSheet: View {
    let stamp: StampBook.Stamp
    let spot: OfficialSpot?
    let spots: [OfficialSpot]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JPSpace.m) {
                    VStack(spacing: JPSpace.xs) {
                        StampPaper {
                            StampView(stamp: stamp, tilted: false)
                                .frame(width: 146, height: 146)
                        }
                        .frame(width: 170)
                        Text(stamp.name)
                            .font(JPFont.cardTitle)
                            .foregroundStyle(WebTheme.foreground)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        if let day = TakenDay.label(stamp.firstDay) {
                            HStack(spacing: JPSpace.xs) {
                                Text(StampBookText.firstDayLabel)
                                    .foregroundStyle(WebTheme.text3)
                                Text(day)
                                    .font(JPFont.caption.monospacedDigit())
                                    .foregroundStyle(WebTheme.text2)
                            }
                            .font(JPFont.caption)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    if !stamp.photos.isEmpty {
                        HStack {
                            JPEyebrowLine(StampBookText.photosHere)
                            Text(StampBookText.photoCount(stamp.photos.count))
                                .font(JPFont.caption)
                                .foregroundStyle(WebTheme.text3)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: JPSpace.xs) {
                                ForEach(stamp.photos) { photo in
                                    NavigationLink {
                                        PhotoDetailView(photo: photo, fromPublicFeed: false, context: stamp.photos)
                                    } label: {
                                        RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
                                            .frame(width: 84, height: 84)
                                            .clipShape(RoundedRectangle(cornerRadius: JPRadius.xs))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(photo.accessibilityText)
                                }
                            }
                        }
                    }
                    if let spot {
                        JPCard {
                            NavigationLink {
                                OfficialSpotView(spot: spot, spots: spots, photos: [], photosKnown: false)
                            } label: {
                                JPRowLabel(title: StampBookText.openSpot)
                            }
                            .buttonStyle(JPRowButtonStyle())
                            .accessibilityIdentifier("stampBook.detail.spot")
                        }
                    }
                }
                .padding(.horizontal, JPSpace.l)
                .padding(.top, JPSpace.m)
                .padding(.bottom, JPSpace.xl)
            }
            .webScreen()
            .navigationTitle(stamp.placeName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
            }
        }
        .accessibilityIdentifier("stampBook.detail")
    }
}
